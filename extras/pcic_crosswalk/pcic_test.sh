#!/bin/bash
set -euo pipefail

# Tests for the job's period flow, its export into the pcic schema and the loads
# (NewGraphEnvironment/fwapg#25), on a fixture of four sub-basins and seven
# segments, so they run in seconds with no download:
#   - the day bins: n_days, and the week edges the README states;
#   - monthly and weekly segment flow (sql/pcic_crosswalk08_periods.sql and
#     09_discharge.sql) against the mean of every day's routed flow over
#     1981-2010, clamped after averaging;
#   - the README's any-window query, against the same;
#   - every refusal in sql/pcic_export.sql, load/pcic.sql and load/pcic_run.sql
#     but pcic_run.sql's table-name check, which a file never reaches: one with
#     another table's columns fails HEADER MATCH first.
# Needs a PostgreSQL 15+ server, in $PGSERVER as a URL with no database (e.g.
# postgresql://postgres:postgres@localhost:5432). Creates two scratch databases
# on it, pcic_test and pcic_test_load, and drops them on exit.

: "${PGSERVER:?set PGSERVER to a server URL with no database}"
cd "$(dirname "$0")" || exit 1
S=$(mktemp -d -t pcic_test.XXXXXX)
finished=0
cleanup() {
  psql "$PGSERVER/postgres" -X -q -c "DROP DATABASE IF EXISTS pcic_test" -c "DROP DATABASE IF EXISTS pcic_test_load" > /dev/null 2>&1 || true
  rm -rf "$S"
  [ "$finished" = 1 ] || echo "ABORTED: a setup step failed (above), so the tests did not all run"
}
trap cleanup EXIT
fails=0

psql "$PGSERVER/postgres" -X -q -c "DROP DATABASE IF EXISTS pcic_test" -c "CREATE DATABASE pcic_test" \
  -c "DROP DATABASE IF EXISTS pcic_test_load" -c "CREATE DATABASE pcic_test_load"
P="psql $PGSERVER/pcic_test -X -q -v ON_ERROR_STOP=1"
Q="psql $PGSERVER/pcic_test_load -X -q -v ON_ERROR_STOP=1"

check() {  # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected '$2', got '$3'"; fails=$((fails + 1)); fi
}
checks() {  # checks <number expected>, with "description|t or f" lines on stdin
  local out n=0 line
  out=$(cat)
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    n=$((n + 1))
    if [ "${line##*|}" = t ]; then echo "ok   ${line%|*}"; else echo "FAIL ${line%|*}"; fails=$((fails + 1)); fi
  done <<< "$out"
  [ "$n" -eq "$1" ] || { echo "FAIL expected $1 checks, got $n"; fails=$((fails + 1)); }
}
refused() {  # refused <description> <message pattern> <command ...>
  local out rc=0
  out=$("${@:3}" 2>&1) || rc=$?
  if [ "$rc" -ne 0 ] && grep -q -- "$2" <<< "$out"; then
    echo "ok   $1"
  else
    echo "FAIL $1: exit $rc, output:"; echo "$out" | sed 's/^/     /'; fails=$((fails + 1))
  fi
}
succeeds() {  # succeeds <description> <command ...>
  local out rc=0
  out=$("${@:2}" 2>&1) || rc=$?
  if [ "$rc" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1: exit $rc, output:"; echo "$out" | sed 's/^/     /'; fails=$((fails + 1)); fi
}

# ----------
# day bins
# ----------
$P -c "CREATE EXTENSION ltree" -c "CREATE SCHEMA fwapg"
$P -v y1=1981 -v y2=1983 -f sql/pcic_crosswalk01_days.sql
checks 1 < <($P -tA -c "SELECT 'a period with no leap year gives Feb 29 no days', bool_and(n_days = CASE WHEN (month, day) = (2, 29) THEN 0 ELSE 3 END) AND count(*) = 366 FROM fwapg.pcic_day_bins")
$P -v y1=1981 -v y2=2010 -f sql/pcic_crosswalk01_days.sql
checks 6 < <($P -tA <<'SQL'
SELECT '366 calendar days, Feb 29 on 7 of 1981-2010, every other day on 30',
  count(*) = 366 AND bool_and(n_days = CASE WHEN (month, day) = (2, 29) THEN 7 ELSE 30 END)
FROM fwapg.pcic_day_bins;
SELECT '52 weeks, each of 7 calendar days but week 9 (8 with Feb 29) and week 52 (8)',
  count(*) = 52 AND bool_and(n = CASE WHEN week IN (9, 52) THEN 8 ELSE 7 END)
FROM (SELECT week, count(*) AS n FROM fwapg.pcic_day_bins GROUP BY week) w;
SELECT 'week 1 is Jan 1-7', string_agg(week::text, ',' ORDER BY day) = '1,1,2'
FROM fwapg.pcic_day_bins WHERE month = 1 AND day IN (1, 7, 8);
SELECT 'week 9 is Feb 26 - Mar 4 and holds Feb 29', string_agg(week::text, ',' ORDER BY month, day) = '8,9,9,9,10'
FROM fwapg.pcic_day_bins WHERE (month, day) IN ((2, 25), (2, 26), (2, 29), (3, 4), (3, 5));
SELECT 'week 52 is Dec 24-31', string_agg(week::text, ',' ORDER BY day) = '51,52,52'
FROM fwapg.pcic_day_bins WHERE month = 12 AND day IN (23, 24, 31);
SELECT 'weeks run in calendar order', bool_and(week >= prev)
FROM (SELECT week, lag(week, 1, 1) OVER (ORDER BY month, day) AS prev FROM fwapg.pcic_day_bins) w;
SQL
)

# ----------
# period flow: sub-basins 1 and 3 drain to 2, and 2 to 4; flow depends on the
# calendar day only
# ----------
$P <<'SQL'
CREATE TABLE fwapg.pcic_outlet_daily AS
SELECT s.subid, b.month, b.day, (s.subid * 10 + b.month + b.day / 100.0)::float8 AS q_m3s
FROM (VALUES (1), (2), (3), (4)) s(subid), fwapg.pcic_day_bins b;
-- sub-basin 2's local flow is negative through winter and crosses zero within May
CREATE TABLE fwapg.pcic_subbasins_daily AS
WITH l AS (
  SELECT s.subid, b.month, b.day,
    (CASE s.subid WHEN 2 THEN b.month - 6 + b.day / 10.0 WHEN 4 THEN 0.5 * b.month + b.day / 20.0 ELSE s.subid + b.month + b.day / 100.0 END)::float8 AS q_local
  FROM (VALUES (1), (2), (3), (4)) s(subid), fwapg.pcic_day_bins b
)
SELECT l.subid, l.month, l.day, l.q_local,
  (SELECT sum(x.q_local) FROM l x WHERE (x.month, x.day) = (l.month, l.day)
    AND x.subid = ANY(CASE l.subid WHEN 2 THEN '{1,2,3}'::integer[] WHEN 4 THEN '{1,2,3,4}' ELSE ARRAY[l.subid] END)) AS q_acc
FROM l;
CREATE TABLE fwapg.pcic_segment_weights (linear_feature_id bigint PRIMARY KEY, watershed_group_code text, subid integer, share double precision, upstream_subids integer[]);
INSERT INTO fwapg.pcic_segment_weights VALUES
  (100, 'BULK', 1, 1, '{}'), (110, 'BULK', 3, 0.4, '{}'),
  (200, 'BULK', 2, 1, '{1,3}'), (250, 'BULK', 2, 0.25, '{1,3}'), (300, 'BULK', 2, 0.5, '{}'),
  (400, 'BULK', 4, 1, '{2}'), (450, 'BULK', 4, 0.5, '{2}');
SQL
for st in month:monthly week:weekly; do
  step=${st%:*}; table=${st#*:}
  $P -v step=$step -v table=$table -f sql/pcic_crosswalk08_periods.sql
  $P -c "CREATE TABLE fwapg.pcic_discharge_$table (linear_feature_id bigint, watershed_group_code text, $step integer, q_raw double precision, q_m3s double precision, PRIMARY KEY (linear_feature_id, $step))"
  $P -v wsg=BULK -v step=$step -v table=$table -f sql/pcic_crosswalk09_discharge.sql
done
# the reference: each segment's routed flow on every day of 1981-2010, and that
# day's week found from its date (Feb 29 counted as Feb 28)
$P <<'SQL'
CREATE TABLE routed_daily AS
SELECT w.linear_feature_id, g.d::date AS d,
  extract(month FROM g.d)::integer AS month,
  least((g.d::date - date_trunc('year', g.d)::date
    - CASE WHEN extract(day FROM date_trunc('year', g.d) + interval '2 months' - interval '1 day') = 29 AND g.d::date > make_date(extract(year FROM g.d)::integer, 2, 28) THEN 1 ELSE 0 END) / 7 + 1, 52) AS week,
  extract(month FROM g.d)::integer * 100 + extract(day FROM g.d)::integer AS mmdd,
  coalesce((SELECT sum(u.q_acc) FROM fwapg.pcic_subbasins_daily u
    WHERE u.subid = ANY(w.upstream_subids) AND (u.month, u.day) = (extract(month FROM g.d)::integer, extract(day FROM g.d)::integer)), 0)
  + s.q_local * w.share AS q
FROM fwapg.pcic_segment_weights w
CROSS JOIN generate_series('1981-01-01'::date, '2010-12-31'::date, interval '1 day') g(d)
INNER JOIN fwapg.pcic_subbasins_daily s ON s.subid = w.subid AND (s.month, s.day) = (extract(month FROM g.d)::integer, extract(day FROM g.d)::integer);
SQL
checks 8 < <($P -tA <<'SQL'
SELECT 'outlet monthly flow is the mean of every day of 1981-2010',
  count(*) = 48 AND max(abs(o.q_m3s - r.q)) < 1e-9
FROM fwapg.pcic_outlet_monthly o
INNER JOIN (
  SELECT q.subid, extract(month FROM g.d)::integer AS month, avg(q.q_m3s) AS q
  FROM fwapg.pcic_outlet_daily q
  INNER JOIN generate_series('1981-01-01'::date, '2010-12-31'::date, interval '1 day') g(d)
    ON (q.month, q.day) = (extract(month FROM g.d)::integer, extract(day FROM g.d)::integer)
  GROUP BY 1, 2
) r USING (subid, month);
SELECT 'segment monthly flow is the mean of every day''s routed flow, clamped after averaging',
  count(*) = 84 AND (SELECT count(*) FROM fwapg.pcic_discharge_monthly) = 84
  AND max(abs(p.q_raw - r.q)) < 1e-9
  AND max(abs(p.q_m3s - round(greatest(r.q, 0)::numeric, 5)::float8)) < 1e-12
FROM fwapg.pcic_discharge_monthly p
INNER JOIN (SELECT linear_feature_id, month, avg(q) AS q FROM routed_daily GROUP BY 1, 2) r USING (linear_feature_id, month);
SELECT 'segment weekly flow is the mean of every day''s routed flow, clamped after averaging',
  count(*) = 364 AND (SELECT count(*) FROM fwapg.pcic_discharge_weekly) = 364
  AND max(abs(p.q_raw - r.q)) < 1e-9
  AND max(abs(p.q_m3s - round(greatest(r.q, 0)::numeric, 5)::float8)) < 1e-12
FROM fwapg.pcic_discharge_weekly p
INNER JOIN (SELECT linear_feature_id, week, avg(q) AS q FROM routed_daily GROUP BY 1, 2) r USING (linear_feature_id, week);
SELECT 'a segment whose January mean is negative is clamped to 0', q_raw < 0 AND q_m3s = 0
FROM fwapg.pcic_discharge_monthly WHERE linear_feature_id = 300 AND month = 1;
SELECT 'the fixture crosses zero within May on segment 300, so a clamp per day would differ',
  min(q) < 0 AND max(q) > 0 AND avg(q) > 0 AND avg(greatest(q, 0)) > avg(q) + 0.01
FROM routed_daily WHERE linear_feature_id = 300 AND month = 5;
SELECT 'no negative flow', bool_and(q_m3s >= 0)
FROM (SELECT q_m3s FROM fwapg.pcic_discharge_monthly UNION ALL SELECT q_m3s FROM fwapg.pcic_discharge_weekly) q;
SELECT 'an outlet segment carries the flow accumulated at its outlet',
  count(*) = 24 AND max(abs(p.q_m3s - round(greatest(s.q_acc, 0)::numeric, 5)::float8)) < 1e-12
FROM fwapg.pcic_discharge_monthly p INNER JOIN fwapg.pcic_subbasins_monthly s
  ON (s.subid, p.linear_feature_id) IN ((2, 200), (4, 400)) AND s.month = p.month;
SELECT 'an upstream sub-basin that is not a headwater adds its accumulated flow, not its local flow',
  bool_and(abs(u.q_acc - u.q_local) > 1)
FROM fwapg.pcic_subbasins_monthly u WHERE u.subid = 2;
SQL
)

# ----------
# export into pcic
# ----------
sed -n '/^CREATE TABLE fwapg.pcic_fwa_crosswalk (/,/^);/p' sql/pcic_crosswalk04_select.sql | $P
$P -c "INSERT INTO fwapg.pcic_fwa_crosswalk (subid, dowsubid, flag, linear_feature_id) VALUES (1, 2, NULL, 100), (2, 4, NULL, 200), (3, 2, NULL, 110), (4, -1, NULL, 400)"
$P -f ../../load/pcic_schema.sql
export_run() {  # export_run <model> <period> <weekly 0|1>
  $P -v model="$1" -v scenario=historical -v period="$2" -v weekly="$3" -f sql/pcic_export.sql
}
succeeds 'export PNWNAmet 1981-2010 with weekly flow' export_run PNWNAmet 1981-2010 1
# what the export wrote is its staging tables, row for row
same() {  # same <description> <query a> <query b>: equal and not empty
  echo "SELECT '$1', (SELECT count(*) FROM ($2) a) > 0
    AND NOT EXISTS (($2) EXCEPT ALL ($3)) AND NOT EXISTS (($3) EXCEPT ALL ($2));"
}
R="model = 'PNWNAmet' AND scenario = 'historical' AND period = '1981-2010'"
checks 6 < <({
  same 'the export writes the monthly flow' "SELECT linear_feature_id, watershed_group_code, month, q_m3s FROM pcic.discharge_monthly WHERE $R" \
    "SELECT linear_feature_id, watershed_group_code, month, q_m3s FROM fwapg.pcic_discharge_monthly"
  same 'the export writes the weekly flow' "SELECT linear_feature_id, watershed_group_code, week, q_m3s FROM pcic.discharge_weekly WHERE $R" \
    "SELECT linear_feature_id, watershed_group_code, week, q_m3s FROM fwapg.pcic_discharge_weekly"
  same 'the export writes the sub-basin daily flow and n_days' "SELECT subid, month, day, n_days, q_local, q_acc FROM pcic.subbasin_daily WHERE $R" \
    "SELECT d.subid, d.month, d.day, b.n_days, d.q_local, d.q_acc FROM fwapg.pcic_subbasins_daily d INNER JOIN fwapg.pcic_day_bins b USING (month, day)"
  same 'the export writes the day bins' "SELECT month, day, week FROM pcic.day_bins" "SELECT month, day, week FROM fwapg.pcic_day_bins"
  same 'the export writes the crosswalk' "SELECT * FROM pcic.fwa_crosswalk" "SELECT * FROM fwapg.pcic_fwa_crosswalk"
  same 'the export writes the weights' "SELECT * FROM pcic.segment_weights" "SELECT * FROM fwapg.pcic_segment_weights"
} | $P -tA)

# a second run, whose flow differs from the first's in every table
$P -c "UPDATE fwapg.pcic_discharge_monthly SET q_m3s = q_m3s * 2" -c "UPDATE fwapg.pcic_discharge_weekly SET q_m3s = q_m3s * 2" \
  -c "UPDATE fwapg.pcic_subbasins_daily SET q_local = q_local + 1, q_acc = q_acc + 1"
succeeds 'export a second run, with weekly flow' export_run PNWNAmet 1951-2012 1
succeeds 'export it again, without weekly flow' export_run PNWNAmet 1951-2012 0
check 'a run exported again without weekly flow loses its weekly rows' '0|' \
  "$($P -tA -c "SELECT (SELECT count(*) FROM pcic.discharge_weekly WHERE period = '1951-2012'), (SELECT weekly_rows FROM pcic.runs WHERE period = '1951-2012')")"
succeeds 'export it again, with weekly flow' export_run PNWNAmet 1951-2012 1

# the README's query for flow over any window, for the first run while the second
# is in pcic too, against the mean of every day in
# the window (Jul 15 - Sep 7) of each segment's routed flow, clamped after
awk '/^```sql$/ { f = 1; next } /^```$/ { f = 0 } f' README.md | sed '$ s/;[[:space:]]*$//' > "$S/window.sql"
check 'the README holds one window query' 1 "$(grep -c '^WITH window_flow AS' "$S/window.sql" || true)"
# and the same query over Jan 15 - Mar 7, which holds Feb 29 and a negative mean
window_check() {  # window_check <description> <first mmdd> <last mmdd> <query file>
  { echo "CREATE TEMPORARY TABLE readme_window AS"; cat "$4"; echo ";"
    echo "SELECT '$1', count(*) = 7 AND max(abs(w.q_m3s - greatest(r.q, 0))) < 1e-9"
    echo "FROM readme_window w INNER JOIN (SELECT linear_feature_id, avg(q) AS q FROM routed_daily"
    echo "  WHERE mmdd BETWEEN $2 AND $3 GROUP BY 1) r USING (linear_feature_id);"
  } > "$S/window_check.sql"
  $P -tA -f "$S/window_check.sql"
}
sed "s/'2001-07-15'/'2001-01-15'/; s/'2001-09-07'/'2001-03-07'/" "$S/window.sql" > "$S/window_winter.sql"
check 'the winter window replaced both dates' 2 "$(grep -o "'2001-0[13]-[01][57]'" "$S/window_winter.sql" | wc -l | tr -d ' ')"
checks 3 < <(
  window_check 'the README window query gives the clamped mean of every day in the window' 715 907 "$S/window.sql"
  window_check 'the README window query over a winter window, with Feb 29 and a negative mean' 115 307 "$S/window_winter.sql"
  $P -tA -c "SELECT 'the winter window has a segment whose mean is negative', min(q) < 0 FROM (SELECT avg(q) AS q FROM routed_daily WHERE mmdd BETWEEN 115 AND 307 GROUP BY linear_feature_id) r"
)


$P -c "UPDATE fwapg.pcic_fwa_crosswalk SET flag = 'demoted' WHERE subid = 3"
refused 'export: a crosswalk unlike the other runs'"'"' is refused' 'crosswalk or weights differ' export_run X 1981-2010 0
$P -c "UPDATE fwapg.pcic_fwa_crosswalk SET flag = NULL WHERE subid = 3"
$P -c "UPDATE fwapg.pcic_segment_weights SET share = 0.5 WHERE linear_feature_id = 250"
refused 'export: weights unlike the other runs'"'"' are refused' 'crosswalk or weights differ' export_run X 1981-2010 0
$P -c "UPDATE fwapg.pcic_segment_weights SET share = 0.25 WHERE linear_feature_id = 250"
$P -c "INSERT INTO fwapg.pcic_segment_weights VALUES (999, 'BULK', 1, 0, '{}')"
refused 'export: weights with an added row of share 0 are refused' 'crosswalk or weights differ' export_run X 1981-2010 0
$P -c "DELETE FROM fwapg.pcic_segment_weights WHERE linear_feature_id = 999"
# a row of a run pcic.runs does not list, in each table that holds runs
ghost() {  # ghost <table>: an INSERT of one such row
  case $1 in
    subbasin_daily) echo "INSERT INTO pcic.subbasin_daily VALUES ('Ghost', 'historical', '2000-2001', 1, 1, 1, 1, 1.0, 1.0)" ;;
    discharge_monthly|discharge_weekly) echo "INSERT INTO pcic.$1 VALUES ('Ghost', 'historical', '2000-2001', 100, 'BULK', 1, 1.0)" ;;
  esac
}
for t in subbasin_daily discharge_monthly discharge_weekly; do
  $P -c "$(ghost $t)"
  refused "export: rows in pcic.$t of a run pcic.runs does not list are refused" 'that pcic.runs does not list' export_run X 1981-2010 0
  $P -c "DELETE FROM pcic.$t WHERE model = 'Ghost'"
done
check 'the refused exports changed nothing' 'PNWNAmet 1951-2012, PNWNAmet 1981-2010' \
  "$($P -tA -c "SELECT string_agg(model || ' ' || period, ', ' ORDER BY period) FROM pcic.runs")"

# ----------
# load the exported files into a second database
# ----------
ex() { $P -c "\\copy ($2) TO STDOUT WITH (FORMAT csv, HEADER)" | gzip > "$S/$1.csv.gz"; }
for t in runs day_bins fwa_crosswalk segment_weights; do ex pcic.$t "SELECT * FROM pcic.$t"; done
for per in 1981-2010 1951-2012; do
  for t in subbasin_daily discharge_monthly discharge_weekly; do ex pcic.$t.pnwnamet_historical_$per "SELECT * FROM pcic.$t WHERE period = '$per'"; done
done
# load/pcic.sql, reading the files here instead of fresh-bc
local_load() {  # local_load <directory> <sql file to write>
  sed "s#curl -sSf https://fresh-bc.s3.us-west-2.amazonaws.com/fwapg/extras/\([^ ]*\) | gunzip#gunzip -c $1/\1#" ../../load/pcic.sql > "$2"
  if grep -q curl "$2" || [ "$(grep -c "gunzip -c $1/" "$2")" != 4 ]; then echo "load/pcic.sql has changed its fetch: fix local_load" >&2; exit 1; fi
}
local_load "$S" "$S/pcic_local.sql"
load_run() {  # load_run <table> <file>
  gunzip -c "$2" | $Q -v table="$1" -f ../../load/pcic_run.sql
}
m=$S/pcic.discharge_monthly.pnwnamet_historical_1981-2010.csv.gz
$Q -c "CREATE EXTENSION ltree"
$Q -f ../../load/pcic_schema.sql
succeeds 'load the shared tables' $Q -f "$S/pcic_local.sql"
for per in 1951-2012 1981-2010; do
  for t in subbasin_daily discharge_monthly discharge_weekly; do succeeds "load $t $per" load_run $t "$S/pcic.$t.pnwnamet_historical_$per.csv.gz"; done
done
check 'rows loaded: runs, daily, monthly, weekly, weights' '2|2928|168|728|7' \
  "$($Q -tA -c "SELECT (SELECT count(*) FROM pcic.runs), (SELECT count(*) FROM pcic.subbasin_daily), (SELECT count(*) FROM pcic.discharge_monthly), (SELECT count(*) FROM pcic.discharge_weekly), (SELECT count(*) FROM pcic.segment_weights)")"
for t in runs day_bins fwa_crosswalk segment_weights subbasin_daily discharge_monthly discharge_weekly; do
  a=$($P -tA -c "SELECT count(*) || ' ' || md5(string_agg(t::text, '|' ORDER BY t::text)) FROM pcic.$t t")
  b=$($Q -tA -c "SELECT count(*) || ' ' || md5(string_agg(t::text, '|' ORDER BY t::text)) FROM pcic.$t t")
  if [ "${a%% *}" -gt 0 ] 2>/dev/null; then check "loaded pcic.$t equals the exported one" "$a" "$b"; else check "exported pcic.$t has rows" 'rows' "$a"; fi
done

truncated() { gunzip -c "$m" | head -20 | $Q -v table=discharge_monthly -f ../../load/pcic_run.sql; }
reordered() { gunzip -c "$m" | awk -F, -v OFS=, '{ t = $6; $6 = $7; $7 = t; print }' | $Q -v table=discharge_monthly -f ../../load/pcic_run.sql; }
unlisted() { gunzip -c "$m" | sed 's/1981-2010/1971-2000/' | $Q -v table=discharge_monthly -f ../../load/pcic_run.sql; }
refused 'load: a truncated file is refused' 'does not match pcic.runs' truncated
# a file that differs from its run's fingerprint in one part only
one_part() {  # one_part <rows|keys|sum>
  case $1 in
    rows) { gunzip -c "$m"; echo 'PNWNAmet,historical,1981-2010,100,BULK,13,0'; } ;;
    keys) gunzip -c "$m" | sed '2 s/^\(PNWNAmet,historical,1981-2010,\)[0-9]*,/\1999,/' ;;
    sum) gunzip -c "$m" | awk -F, -v OFS=, 'NR == 2 { $7 = $7 + 1 } { print }' ;;
  esac | $Q -v table=discharge_monthly -f ../../load/pcic_run.sql
}
for part in rows keys sum; do
  refused "load: a file unlike its run in $part alone is refused" 'does not match pcic.runs' one_part $part
done
refused 'load: a file with reordered columns is refused' 'mismatch' reordered
refused 'load: a run not in pcic.runs is refused' 'not in pcic.runs' unlisted

mkdir "$S/other"
cp "$S"/pcic.*.csv.gz "$S/other/"
gunzip -c "$S/pcic.fwa_crosswalk.csv.gz" | sed '2 s/$/demoted/' | gzip > "$S/other/pcic.fwa_crosswalk.csv.gz"
local_load "$S/other" "$S/pcic_other.sql"
refused 'load: a crosswalk file unlike the runs'"'"' is refused' 'is not the crosswalk' $Q -f "$S/pcic_other.sql"
cp "$S/pcic.fwa_crosswalk.csv.gz" "$S/other/"
gunzip -c "$S/pcic.segment_weights.csv.gz" | sed '2 s/,1,{}$/,0.9,{}/' | gzip > "$S/other/pcic.segment_weights.csv.gz"
check 'the weights file was changed' 1 "$(gunzip -c "$S/other/pcic.segment_weights.csv.gz" | grep -c ',0.9,{}$' || true)"
refused 'load: a weights file unlike the runs'"'"' is refused' 'does not match pcic.runs' $Q -f "$S/pcic_other.sql"
{ gunzip -c "$S/pcic.segment_weights.csv.gz"; echo '999,BULK,1,0,{}'; } | gzip > "$S/other/pcic.segment_weights.csv.gz"
refused 'load: a weights file with an added row of share 0 is refused' 'does not match pcic.runs' $Q -f "$S/pcic_other.sql"
cp "$S/pcic.segment_weights.csv.gz" "$S/other/"
gunzip -c "$S/pcic.day_bins.csv.gz" | sed '$d' | gzip > "$S/other/pcic.day_bins.csv.gz"
refused 'load: a day bins file short of 366 days is refused' 'does not hold 366' $Q -f "$S/pcic_other.sql"
cp "$S/pcic.day_bins.csv.gz" "$S/other/"
# each shared file with two columns swapped, header and all
for t in runs fwa_crosswalk segment_weights day_bins; do
  gunzip -c "$S/pcic.$t.csv.gz" | awk -F, -v OFS=, '{ x = $1; $1 = $2; $2 = x; print }' | gzip > "$S/other/pcic.$t.csv.gz"
  refused "load: a pcic.$t file with reordered columns is refused" 'mismatch' $Q -f "$S/pcic_other.sql"
  cp "$S/pcic.$t.csv.gz" "$S/other/"
done
gunzip -c "$S/pcic.runs.csv.gz" | head -1 | gzip > "$S/other/pcic.runs.csv.gz"
refused 'load: a runs file with no runs is refused' 'lists no runs' $Q -f "$S/pcic_other.sql"
cp "$S/pcic.runs.csv.gz" "$S/other/"
# a run built here and not published: kept when it shares the published crosswalk
# and weights, refused when it differs from them in any one part
local_run() {  # local_run <md5 expression> <rows expression> <share sum expression>
  $Q -c "INSERT INTO pcic.runs (model, scenario, period, crosswalk_md5, weights_rows, weights_share_sum)
    SELECT 'Local', scenario, '2000-2001', $1, $2, $3 FROM pcic.runs WHERE period = '1981-2010'"
}
local_run crosswalk_md5 weights_rows weights_share_sum
succeeds 'load: a run here on the same crosswalk and weights, not published, does not stop a reload' $Q -f "$S/pcic_local.sql"
check 'and stays listed' 1 "$($Q -tA -c "SELECT count(*) FROM pcic.runs WHERE model = 'Local'")"
$Q -c "DELETE FROM pcic.runs WHERE model = 'Local'"
for part in "crosswalk_md5 || 'x';weights_rows;weights_share_sum;crosswalk" \
  "crosswalk_md5;weights_rows + 1;weights_share_sum;weights rows" "crosswalk_md5;weights_rows;weights_share_sum + 1;weights share sum"; do
  IFS=';' read -r a b c what <<< "$part"
  local_run "$a" "$b" "$c"
  refused "load: a run here unlike the published in its $what alone is refused" 'built on another crosswalk or weights' $Q -f "$S/pcic_local.sql"
  $Q -c "DELETE FROM pcic.runs WHERE model = 'Local'"
done
two_runs() {
  { gunzip -c "$m"; gunzip -c "$S/pcic.discharge_monthly.pnwnamet_historical_1951-2012.csv.gz" | tail -n +2; } \
    | $Q -v table=discharge_monthly -f ../../load/pcic_run.sql
}
refused 'load: a file holding two runs is refused' 'holds 2 runs' two_runs
$Q -c "UPDATE pcic.fwa_crosswalk SET flag = 'demoted' WHERE subid = 3"
refused 'load: a run built on another crosswalk than pcic.fwa_crosswalk is refused' 'another crosswalk than' load_run discharge_monthly "$m"
$Q -c "UPDATE pcic.fwa_crosswalk SET flag = NULL WHERE subid = 3"

per_run="SELECT period, (SELECT count(*) FROM pcic.subbasin_daily d WHERE d.period = r.period), (SELECT count(*) FROM pcic.discharge_monthly d WHERE d.period = r.period), (SELECT count(*) FROM pcic.discharge_weekly d WHERE d.period = r.period) FROM pcic.runs r ORDER BY period"
# a reload drops a published run's rows of a table whose fingerprint here differs
# from the published one, in any one part, and keeps every other run's and table's
stale() {  # stale <table> <column of pcic.runs> <period> <column of per_run>
  local before want
  before=$($Q -tA -c "$per_run")
  want=$(awk -F'|' -v OFS='|' -v p="$3" -v c="$4" '$1 == p { $c = 0 } { print }' <<< "$before")
  $Q -c "UPDATE pcic.runs SET $2 = $2 + 1 WHERE period = '$3'"
  succeeds "reload with $2 changed for $3" $Q -f "$S/pcic_local.sql"
  check "the reload drops only $3's pcic.$1 rows" "$want" "$($Q -tA -c "$per_run")"
  succeeds "and $3's pcic.$1 file loads again" load_run "$1" "$S/pcic.$1.pnwnamet_historical_$3.csv.gz"
}
check 'both runs have rows in every table before the reloads' "1951-2012|1464|84|364"$'\n'"1981-2010|1464|84|364" "$($Q -tA -c "$per_run")"
stale subbasin_daily daily_rows 1981-2010 2
stale subbasin_daily daily_subbasins 1951-2012 2
stale subbasin_daily daily_q_sum 1981-2010 2
stale discharge_monthly monthly_rows 1951-2012 3
stale discharge_monthly monthly_segments 1981-2010 3
stale discharge_monthly monthly_q_sum 1951-2012 3
stale discharge_weekly weekly_rows 1981-2010 4
stale discharge_weekly weekly_segments 1951-2012 4
stale discharge_weekly weekly_q_sum 1981-2010 4
for t in subbasin_daily discharge_monthly discharge_weekly; do
  $Q -c "$(ghost $t)"
  refused "load: rows in pcic.$t of a run pcic.runs does not list are refused" 'that pcic.runs does not list' $Q -f "$S/pcic_local.sql"
  $Q -c "DELETE FROM pcic.$t WHERE model = 'Ghost'"
done

finished=1
[ "$fails" -eq 0 ] && echo 'all pcic tests pass' || { echo "$fails failed"; exit 1; }
