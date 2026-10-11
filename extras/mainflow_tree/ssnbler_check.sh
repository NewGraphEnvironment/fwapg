#!/bin/bash
set -euo pipefail

# Run ssnbler_check.R on one subset of the main-flow tree, one run at a time,
# killed above a memory cap. See README.md.
#
#   ./ssnbler_check.sh <cap_gb> <name> <wscode> [group] [expected outlets]
#
# Exports the tree segments under <wscode> (within watershed group [group], or
# in every group; "-" for none) to data/ssnbler/<name>.gpkg and builds the
# landscape network in data/ssnbler/lsn_<name>. Memory is the summed footprint
# (resident plus compressed, as top reports it) of R, everything under it and
# this run's SSNbler workers, sampled every 3 s. At 46,340 lines or more SSNbler
# starts a PSOCK cluster: separate R processes, reparented away from R, found by
# the worker log path ssnbler_check.R puts on their command lines. Each run
# appends one line to data/ssnbler/runs.log. Exit status: 0 clean; 1 node errors
# or an outlet count other than expected; 2 bad arguments or a run already going;
# 3 killed at the cap or by low system memory; 4 the memory could not be sampled;
# 5 no result (the export failed, the subset is empty, R failed, or anything else
# went wrong); 129, 130 or 143 when the script itself got HUP, INT or TERM.

# The exit status is $final and nothing else: the EXIT trap always exits with it,
# so a failure no line here anticipated (set -e, set -u, a tool's own status)
# reads as 5, never as a plausible 0 or 1.
final=5
trap 'exit "$final"' EXIT
die() {
  echo "$2" >&2
  final=$1
  exit
}

cd "$(dirname "$0")"

usage="usage: ./ssnbler_check.sh <cap_gb> <name> <wscode> [group|-] [expected outlets]"
[ $# -ge 3 ] && [ $# -le 5 ] || die 2 "$usage"
cap_gb=$1
name=$2
wscode=$3
group=${4:--}
outlets=${5:-}
# the values go into SQL and file names
[[ $cap_gb =~ ^[1-9][0-9]{0,3}$ ]] || die 2 "cap_gb must be a whole number of GB"
[[ $name =~ ^[A-Za-z0-9_]+$ ]] || die 2 "name: letters, digits and _ only"
[[ $wscode =~ ^[0-9]+(\.[0-9]+)*$ ]] || die 2 "wscode must look like 100.567134"
[[ $group == - || $group =~ ^[A-Z]{4}$ ]] || die 2 "group must be a watershed group code or -"
[[ -z $outlets || $outlets =~ ^[0-9]{1,6}$ ]] || die 2 "expected outlets must be a whole number"
[ -n "${DATABASE_URL:-}" ] || die 2 "DATABASE_URL is not set"

dir=data/ssnbler
mkdir -p "$dir"
log=$dir/$name.log
# the worker log ssnbler_check.R sets, as it appears on each worker's command line
# (passed to awk through the environment, so awk's own command line cannot match it)
export WORKER_TAG="OUT=$(pwd -P)/$dir/lsn_$name.workers.log"

# one run at a time: three large networks in memory at once crashed the machine in
# fwapg#2. A lock left by a run that no longer exists (a crash) is taken over.
lock=$dir/.lock
if ! mkdir "$lock" 2> /dev/null; then
  holder=$(cat "$lock/pid" 2> /dev/null || true)
  if [ -n "$holder" ] && kill -0 "$holder" 2> /dev/null; then
    die 2 "ssnbler_check.sh is already running (pid $holder)"
  fi
  echo "taking over the lock of a run that is gone (pid ${holder:-unknown})" >&2
fi
echo $$ > "$lock/pid"

pid=""
workers() {
  ps -axo pid=,command= | awk 'index($0, ENVIRON["WORKER_TAG"]) { print $1 }'
}
# TERM to R and this run's workers, then KILL whatever is left after 10 s
stop_run() {
  local i
  [ -n "$pid" ] || return 0
  kill "$pid" $(workers) 2> /dev/null || true
  for i in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$pid" 2> /dev/null || [ -n "$(workers)" ] || return 0
    sleep 1
  done
  kill -9 "$pid" $(workers) 2> /dev/null || true
}
cleanup() {
  stop_run
  rm -rf "$lock"
}
# "|| true": a failure inside the trap must not replace $final
trap 'cleanup || true; exit "$final"' EXIT
trap 'final=129; exit' HUP
trap 'final=130; exit' INT
trap 'final=143; exit' TERM

where="s.wscode_ltree <@ '$wscode'::ltree"
[ "$group" = - ] || where="$where AND s.watershed_group_code = '$group'"
rm -f "$dir/$name.gpkg"
ogr2ogr -f GPKG "$dir/$name.gpkg" PG:"$DATABASE_URL" -nln streams -sql \
  "SELECT s.linear_feature_id, s.geom FROM whse_basemapping.fwa_stream_networks_sp s
   INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t ON t.linear_feature_id = s.linear_feature_id
   WHERE $where" || die 5 "export of $name failed"
n=$(ogrinfo -ro -q -sql "SELECT count(*) AS n FROM streams" "$dir/$name.gpkg" | awk '/n \(Integer/ { print $NF }') \
  || die 5 "cannot count the segments exported for $name"
[ "${n:-0}" -gt 0 ] || die 5 "no tree segments for $name"

start=$(date +%s)
# $outlets unquoted: an empty value passes no argument
Rscript ssnbler_check.R "$dir/$name.gpkg" "$dir/lsn_$name" $outlets > "$log" 2>&1 &
pid=$!

# Footprint in KB of R, its descendants and this run's workers, or ERR when R is
# not in both listings. top prints sizes as 6224K, 3295M, 112G, sometimes with a
# trailing + or -.
sample() {
  awk -v root="$pid" '
    FNR == NR {
      if ($1 ~ /^[0-9]+$/ && $2 ~ /^[0-9.]+[BKMG][+-]?$/) {
        v = $2; u = v; sub(/[+-]$/, "", u); u = substr(u, length(u), 1); sub(/[BKMG][+-]?$/, "", v)
        mem[$1] = v * (u == "G" ? 1048576 : u == "M" ? 1024 : u == "K" ? 1 : 1 / 1024)
      }
      next
    }
    { p[$1] = $2; if (index($0, ENVIRON["WORKER_TAG"])) w[$1] = 1 }
    END {
      if (!(root in p) || !(root in mem)) { print "ERR"; exit }
      for (q in p) {
        x = q
        while ((x in p) && x != 0 && x != 1 && x != root) x = p[x]
        if (x == root || q in w) t += mem[q]
      }
      printf "%d\n", t
    }' <(top -l 1 -stats pid,mem) <(ps -axo pid=,ppid=,command=)
}

cap_kb=$((cap_gb * 1024 * 1024))
peak=0
killed=""
failures=0
while kill -0 "$pid" 2> /dev/null; do
  kb=$(sample || echo ERR)
  if ! [[ $kb =~ ^[0-9]+$ ]] || [ "$kb" -eq 0 ]; then
    # R may have just exited; otherwise three failed samples in a row stop the run
    kill -0 "$pid" 2> /dev/null || break
    failures=$((failures + 1))
    if [ "$failures" -ge 3 ]; then
      killed="memory could not be sampled ($kb), stopped"
      break
    fi
    sleep 1
    continue
  fi
  failures=0
  [ "$kb" -gt "$peak" ] && peak=$kb
  if [ "$kb" -gt "$cap_kb" ]; then
    killed="over the ${cap_gb} GB cap ($((kb / 1048576)) GB), killed"
    break
  fi
  # the system-wide floor: macOS's own percentage of memory available
  level=$(sysctl -n kern.memorystatus_level 2> /dev/null || echo 100)
  if [ "$level" -lt 10 ]; then
    killed="system memory available at ${level}%, killed"
    break
  fi
  sleep 3
done
if [ -n "$killed" ]; then
  case $killed in memory*) final=4 ;; *) final=3 ;; esac
  echo "$killed" >> "$log" || true
  stop_run
fi
r_rc=0
wait "$pid" || r_rc=$?
pid=""
# R exits 0 clean and 1 for node errors or an outlet mismatch, printing the result
# line either way; any other status, or no result line, is a failure (5)
if [ -z "$killed" ]; then
  if [ "$r_rc" -le 1 ] && grep -q 'node errors: [0-9]' "$log"; then
    final=$r_rc
  fi
fi

lines=$(grep -o 'lines: [0-9]*' "$log" || true)
result=$(grep -o 'node errors: [0-9]*  outlets: [0-9]*' "$log" || true)
summary="$(date '+%F %T') $name wscode=$wscode group=$group exit=$final r_exit=$r_rc peak_gb=$(awk -v k="$peak" 'BEGIN { printf "%.1f", k / 1048576 }') minutes=$((($(date +%s) - start + 59) / 60)) ${lines:-lines: ?} ${result:-node errors: ?}"
# the log first, so a closed stdout cannot lose the line
echo "$summary" >> "$dir/runs.log" || echo "could not append to $dir/runs.log" >&2
echo "$summary" || true
exit
