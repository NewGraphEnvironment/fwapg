#!/bin/bash
set -euo pipefail

# Run ssnbler_check.R on one subset of the main-flow tree, one run at a time,
# killed above a memory cap. See README.md.
#
#   ./ssnbler_check.sh <cap_gb> <name> <wscode> [group] [expected outlets]
#
# Exports the tree segments under <wscode> (within watershed group [group], or
# in every group; "-" for none) to data/ssnbler/<name>.gpkg and builds the
# landscape network in data/ssnbler/lsn_<name>. Memory is the summed RSS of R,
# everything under it and SSNbler's workers (at 46,340 lines or more it starts a
# PSOCK cluster, separate R processes that need not sit under R), sampled every
# 3 s. Each run appends one line to data/ssnbler/runs.log; the exit status is
# R's, or 3 when the run was killed at the cap.

cd "$(dirname "$0")"

usage="usage: ./ssnbler_check.sh <cap_gb> <name> <wscode> [group|-] [expected outlets]"
[ $# -ge 3 ] && [ $# -le 5 ] || { echo "$usage" >&2; exit 2; }
cap_gb=$1
name=$2
wscode=$3
group=${4:--}
outlets=${5:-}
# the values go into SQL and file names
[[ $cap_gb =~ ^[1-9][0-9]{0,3}$ ]] || { echo "cap_gb must be a whole number of GB" >&2; exit 2; }
[[ $name =~ ^[A-Za-z0-9_]+$ ]] || { echo "name: letters, digits and _ only" >&2; exit 2; }
[[ $wscode =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "wscode must look like 100.567134" >&2; exit 2; }
[[ $group == - || $group =~ ^[A-Z]{4}$ ]] || { echo "group must be a watershed group code or -" >&2; exit 2; }
[[ -z $outlets || $outlets =~ ^[0-9]{1,6}$ ]] || { echo "expected outlets must be a whole number" >&2; exit 2; }

dir=data/ssnbler
mkdir -p "$dir"

# one run at a time: two large networks in memory at once crashed the machine in fwapg#2
mkdir "$dir/.lock" 2> /dev/null || { echo "another ssnbler_check.sh run holds $dir/.lock" >&2; exit 2; }
workers=""
cleanup() {
  local w
  for w in $workers; do kill "$w" 2> /dev/null || true; done
  rmdir "$dir/.lock"
}
trap cleanup EXIT

where="s.wscode_ltree <@ '$wscode'::ltree"
[ "$group" = - ] || where="$where AND s.watershed_group_code = '$group'"
rm -f "$dir/$name.gpkg"
ogr2ogr -f GPKG "$dir/$name.gpkg" PG:"$DATABASE_URL" -nln streams -sql \
  "SELECT s.linear_feature_id, s.geom FROM whse_basemapping.fwa_stream_networks_sp s
   INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t ON t.linear_feature_id = s.linear_feature_id
   WHERE $where"

log=$dir/$name.log
start=$(date +%s)
# $outlets unquoted: an empty value passes no argument
Rscript ssnbler_check.R "$dir/$name.gpkg" "$dir/lsn_$name" $outlets > "$log" 2>&1 &
pid=$!

# RSS in KB of R, its descendants and any PSOCK worker (the bracket keeps awk
# from matching its own command line); prints "<total> <worker pids>"
sample() {
  ps -axo pid=,ppid=,rss=,command= | awk -v root="$pid" '
    { p[$1] = $2; r[$1] = $3; if ($0 ~ /work[R]SOCK/) w[$1] = 1 }
    END {
      for (q in p) {
        x = q
        while (x != "" && x != 0 && x != 1 && x != root) x = p[x]
        if (x == root || q in w) { t += r[q]; if (q in w) ws = ws " " q }
      }
      print t + 0, ws
    }'
}

cap_kb=$((cap_gb * 1024 * 1024))
peak=0
killed=0
while kill -0 "$pid" 2> /dev/null; do
  read -r kb new <<< "$(sample)"
  for w in $new; do
    [[ " $workers " == *" $w "* ]] || workers="$workers $w"
  done
  [ "$kb" -gt "$peak" ] && peak=$kb
  if [ "$kb" -gt "$cap_kb" ]; then
    echo "over the ${cap_gb} GB cap ($((kb / 1048576)) GB), killed" >> "$log"
    killed=1
    kill "$pid" $workers 2> /dev/null || true
    break
  fi
  sleep 3
done
rc=0
wait "$pid" || rc=$?
[ "$killed" -eq 0 ] || rc=3

lines=$(grep -o 'lines: [0-9]*' "$log" || true)
result=$(grep -o 'node errors: [0-9]*  outlets: [0-9]*' "$log" || true)
summary="$(date '+%F %T') $name wscode=$wscode group=$group exit=$rc peak_rss_gb=$(awk -v k="$peak" 'BEGIN { printf "%.1f", k / 1048576 }') minutes=$((($(date +%s) - start + 59) / 60)) ${lines:-lines: ?} ${result:-node errors: ?}"
echo "$summary" | tee -a "$dir/runs.log"
exit "$rc"
