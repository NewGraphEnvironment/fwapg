#!/bin/bash
# Downstream query benchmark for #34: ltree (L1, L2), the blue line path arrays
# (A-pred, A) and a downstream_id pointer walk (P). The method is in the issue
# body under "## Plan".
#
# Usage: DATABASE_URL=... bench.sh <step> [args]
#
#   env                 settings, sizes and network assertions (sql/00_env.sql)
#   origins             fwapg.bench_origins (sql/00_origins.sql)
#   hope                the shipped trace from Hope, warm, 1 + 3 runs
#   paths               re-time extras/blue_line_paths with sorted-row md5s
#   ids                 build fwapg.downstream_ids, then its QA
#   cell M W C S        one timing cell: method, walk, cell, settings
#   setup               timing tables and the cell matrix (sql/06_timings.sql)
#   timings             every cell in fwapg.bench_cells, at defaults then noparallel
#   summary             medians, p95, timeouts and projections per cell (sql/08_summary.sql)
#   explain             EXPLAIN (ANALYZE, BUFFERS) at 1 and 1,000 origins
#   results             each method's rows for the comparison samples (fwapg.bench_res)
#   compare             correctness: set, order and distance into fwapg.bench_diffs
#
# BENCH_TIMEOUT overrides a cell's statement timeout (default 30min).
#
# One psql call per step and per cell, so a statement timeout ends that cell
# only: it is recorded in fwapg.bench_timings and the run continues. No set -x:
# the connection comes from the environment and the URL is redacted from logs.

set -euo pipefail

: "${DATABASE_URL:?set DATABASE_URL}"

here="$(cd "$(dirname "$0")" && pwd)"
sql="$here/sql"
logs="$(cd "$here/.." && pwd)/logs"
mkdir -p "$logs"

stamp() { date -u +%Y%m%dT%H%M%SZ; }

# the URL (and so any password in it) never reaches a log
# and no home directory path does either (a public repo)
redact() { perl -pe 'BEGIN { $| = 1; $u = $ENV{DATABASE_URL}; $h = $ENV{HOME} } s/\Q$u\E/<DATABASE_URL>/g; s/\Q$h\E/~/g'; }

# psql with the URL from the environment; -X ignores ~/.psqlrc
run_psql() { psql -X -q "$DATABASE_URL" "$@"; }

# run a step, tee it to its log, keep psql's exit status
logged() {
  local name="$1"; shift
  local log
  log="$logs/${name}_$(stamp).log"
  echo "log: $log" >&2
  set +e
  "$@" 2>&1 | redact | tee "$log"
  local rc=${PIPESTATUS[0]}
  set -e
  return "$rc"
}

# timed steps wait until no other client query is active: an orphaned 26 h
# query holding 7 cores ran through the first Hope measurement
wait_idle() {
  local busy
  while :; do
    busy=$(run_psql -At -c "SELECT count(*) FROM pg_stat_activity
      WHERE backend_type = 'client backend' AND pid != pg_backend_pid() AND state != 'idle'")
    [ "$busy" = 0 ] && return 0
    echo "waiting: $busy other active client queries ($(date -u +%H:%M:%SZ))" >&2
    sleep 60
  done
}

# a QA file whose every line must end in |t (a NULL result prints "name|" and fails)
qa_check() {
  local out="$1"
  if [ -z "$out" ] || grep -qv '|t$' <<< "$out"; then
    echo "QA failed" >&2
    return 1
  fi
}

# one timing cell: a warm-up, then n repeats, in one psql call. A statement
# timeout is recorded (ms null, note timeout) and ends the cell, not the run.
# The cell's origin set and repeats come from fwapg.bench_cells (06_timings.sql).
cell_script() {
  local method="$1" walk="$2" cell="$3" settings="$4"
  local spec
  # on stdin: psql -c does not interpolate variables
  spec=$(echo "SELECT grp, lo, hi, repeats, warm, per_origin FROM fwapg.bench_cells WHERE method = :'method' AND walk = :'walk' AND cell = :'cell'" |
    run_psql -At -v ON_ERROR_STOP=1 -v method="$method" -v walk="$walk" -v cell="$cell" -f -)
  if [ -z "$spec" ]; then
    echo "no cell $method/$walk/$cell in fwapg.bench_cells" >&2
    return 1
  fi
  local grp lo hi repeats warm per_origin
  IFS='|' read -r grp lo hi repeats warm per_origin <<< "$spec"
  local walkfile
  case "$method" in
    L1|L2) walkfile=02_walk_ltree.sql ;;
    A-pred|A) walkfile=03_walk_arrays.sql ;;
    P) walkfile=04_walk_pointer.sql ;;
    *) echo "unknown method $method" >&2; return 1 ;;
  esac
  cat <<SQL
\\set method '$method'
\\set walk '$walk'
\\set cell '$cell'
\\set settings '$settings'
\\set grp '$grp'
\\set sink_open 'SELECT count(*) AS n, bit_xor(origin_id::bigint) AS x_origin, bit_xor(linear_feature_id) AS x_segment, sum(ord::bigint) AS s_ord, sum(cum_m) AS s_cum FROM ('
\\set sink_close ') AS walk_rows'
\\set sink_gset true
SET statement_timeout = '${BENCH_TIMEOUT:-30min}';
-- a re-run replaces the cell's earlier rows (its earlier logs stay)
DELETE FROM fwapg.bench_timings
WHERE method = :'method' AND walk = :'walk' AND cell = :'cell' AND settings = :'settings';
-- the walk files' dispatch flags, set here so no query of theirs falls inside the timed interval
\\set dispatch_given true
\\set is_l1 $( [ "$method" = L1 ] && echo true || echo false )
\\set is_pred $( [ "$method" = A-pred ] && echo true || echo false )
\\set is_1km $( [ "$walk" = 1km ] && echo true || echo false )
SQL
  if [ "$settings" = noparallel ]; then
    echo "SET max_parallel_workers_per_gather = 0;"
  fi
  # a per-origin cell times each origin of its set as one statement
  local origins
  if [ "$per_origin" = t ]; then origins=$(seq "$lo" "$hi"); else origins=all; fi
  local first_rep=1 r k
  [ "$warm" = t ] && first_rep=0
  for k in $origins; do
    for r in $(seq "$first_rep" "$repeats"); do
      if [ "$k" = all ]; then
        printf '\\set lo %s\n\\set hi %s\n\\set origin_rank NULL\n' "$lo" "$hi"
      else
        printf '\\set lo %s\n\\set hi %s\n\\set origin_rank %s\n' "$k" "$k" "$k"
      fi
      cat <<SQL
\\set rep $r
SELECT clock_timestamp() AS t0 \\gset
\\i $walkfile
\\if :ERROR
  INSERT INTO fwapg.bench_timings (method, walk, cell, settings, origin_rank, rep, ms, rows, note)
  VALUES (:'method', :'walk', :'cell', :'settings', :origin_rank, :rep, NULL, NULL,
    CASE WHEN :'LAST_ERROR_SQLSTATE' = '57014' THEN 'timeout' ELSE 'error: ' || :'LAST_ERROR_MESSAGE' END);
  SELECT format('%s %s %s %s origin %s rep %s: %s', :'method', :'walk', :'cell', :'settings', :'origin_rank', :rep, :'LAST_ERROR_MESSAGE');
  \\q
\\else
  INSERT INTO fwapg.bench_timings (method, walk, cell, settings, origin_rank, rep, ms, rows, note)
  VALUES (:'method', :'walk', :'cell', :'settings', :origin_rank, :rep,
    extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000, :n,
    CASE WHEN :rep = 0 THEN 'warm-up' END);
  SELECT format('%s %s %s %s origin %s rep %s: %s rows, %s ms', :'method', :'walk', :'cell', :'settings', :'origin_rank', :rep, :n,
    round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz)::numeric * 1000, 1));
\\endif
SQL
    done
  done
}

run_cell() {
  local script
  script=$(mktemp "${TMPDIR:-/tmp}/bench_cell.XXXXXX")
  if ! cell_script "$@" > "$script"; then
    rm -f "$script"
    return 1
  fi
  # no ON_ERROR_STOP: the script reads :ERROR itself; cd so \ir resolves
  (cd "$sql" && run_psql -At -f "$script" < /dev/null)
  local rc=$?
  rm -f "$script"
  return $rc
}

# the whole run is one function, called on the last line: bash reads a script
# as it runs, and an edit to this file during a long run would otherwise be read
# mid-flight
main() {
  step="${1:-}"
  shift || true

  case "$step" in
    env)
      logged env run_psql -At -v ON_ERROR_STOP=1 -f "$sql/00_env.sql"
      ;;
    origins)
      logged origins run_psql -At -v ON_ERROR_STOP=1 -f "$sql/00_origins.sql" -f "$sql/00_origins_hope.sql"
      ;;
    hope)
      wait_idle
      logged hope run_psql -At -v ON_ERROR_STOP=1 -f "$sql/00_hope.sql"
      ;;
    paths)
      wait_idle
      logged paths bash -c '
        set -euo pipefail
        md5() { psql -X -q "$DATABASE_URL" -At -v ON_ERROR_STOP=1 -f "$1/00_paths_md5.sql"; }
        # the tables as they were, for a row diff if the md5s differ
        psql -X -q "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
          DROP TABLE IF EXISTS fwapg.bench_blk_parents_before, fwapg.bench_blk_paths_before;
          CREATE TABLE fwapg.bench_blk_parents_before AS SELECT * FROM fwapg.blk_parents;
          CREATE TABLE fwapg.bench_blk_paths_before AS SELECT * FROM fwapg.blk_paths;"
        echo "before:"; md5 "$1"
        t0=$(date +%s)
        echo "build start $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        "$(git -C "$1" rev-parse --show-toplevel)/extras/blue_line_paths/blue_line_paths.sh" 2>&1 | sed "/^+ /d"
        echo "build end $(date -u +%Y-%m-%dT%H:%M:%SZ), wall $(( $(date +%s) - t0 )) s"
        echo "after:"; md5 "$1"
      ' _ "$sql"
      ;;
    ids)
      wait_idle
      logged ids run_psql -At -v ON_ERROR_STOP=1 -f "$sql/01_downstream_ids.sql"
      out=$(logged ids_qa run_psql -At -v ON_ERROR_STOP=1 -f "$sql/01_qa.sql" | grep '^assert:')
      qa_check "$out"
      ;;
    setup)
      logged setup run_psql -At -v ON_ERROR_STOP=1 -f "$sql/06_timings.sql"
      ;;
    cell)
      wait_idle
      [ $# -eq 4 ] || { echo "usage: bench.sh cell METHOD WALK CELL SETTINGS" >&2; exit 2; }
      logged "cell_${1}_${2}_${3}_${4}" run_cell "$@"
      ;;
    timings)
      # every cell in fwapg.bench_cells, at defaults first
      for settings in default noparallel; do
        run_psql -At -v ON_ERROR_STOP=1 -c "SELECT method, walk, cell FROM fwapg.bench_cells ORDER BY run_order" |
        while IFS='|' read -r m w c; do
          wait_idle
          logged "cell_${m}_${w}_${c}_${settings}" run_cell "$m" "$w" "$c" "$settings" || true
        done
      done
      ;;
    summary)
      logged summary run_psql -At -v ON_ERROR_STOP=1 -f "$sql/08_summary.sql"
      ;;
    explain)
      wait_idle
      logged explain bash -c 'cd "$1" && psql -X -q "$DATABASE_URL" -v ON_ERROR_STOP=1 -f 05_explain.sql' _ "$sql"
      ;;
    results)
      # untimed: no wait for an idle server
      logged results bash -c 'cd "$1" && psql -X -q "$DATABASE_URL" -At -v ON_ERROR_STOP=1 -f 07_results.sql' _ "$sql"
      ;;
    compare)
      logged compare bash -c 'cd "$1" && psql -X -q "$DATABASE_URL" -At -v ON_ERROR_STOP=1 -f 07_compare.sql' _ "$sql"
      ;;
    *)
      sed -n '2,20p' "$0" >&2
      exit 2
      ;;
  esac
}

main "$@"; exit $?
