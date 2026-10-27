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
#     another table's columns fails HEADER MATCH first;
#   - the per-year days (NewGraphEnvironment/fwapg#42), on a fixture of five
#     outlets in two synthetic NetCDF files: sql/pcic_crosswalk06_daily.sql
#     against hand-computed flows, pcic_days.py rows against the job's cdo path,
#     days_build.sh's files read back, their catalogue line, sql/qa_days.sql,
#     sql/qa_report_days.sql's clamp count, and the refusals of pcic_days.py and
#     sql/pcic_export_days.sql.
# Needs a PostgreSQL 15+ server, in $PGSERVER as a URL with no database (e.g.
# postgresql://postgres:postgres@localhost:5432), and uv, cdo and ncdump. Creates
# three scratch databases on it, pcic_test, pcic_test_load and pcic_test_days,
# and drops them on exit.

: "${PGSERVER:?set PGSERVER to a server URL with no database}"
for tool in uv cdo ncdump; do
  command -v $tool > /dev/null || { echo "pcic_test.sh needs $tool" >&2; exit 1; }
done
cd "$(dirname "$0")" || exit 1
S=$(mktemp -d -t pcic_test.XXXXXX)
finished=0
cleanup() {
  psql "$PGSERVER/postgres" -X -q -c "DROP DATABASE IF EXISTS pcic_test" -c "DROP DATABASE IF EXISTS pcic_test_load" \
    -c "DROP DATABASE IF EXISTS pcic_test_days" > /dev/null 2>&1 || true
  rm -rf "$S"
  [ "$finished" = 1 ] || echo "ABORTED: a setup step failed (above), so the tests did not all run"
}
trap cleanup EXIT
fails=0

psql "$PGSERVER/postgres" -X -q -c "DROP DATABASE IF EXISTS pcic_test" -c "CREATE DATABASE pcic_test" \
  -c "DROP DATABASE IF EXISTS pcic_test_load" -c "CREATE DATABASE pcic_test_load" \
  -c "DROP DATABASE IF EXISTS pcic_test_days" -c "CREATE DATABASE pcic_test_days"
P="psql $PGSERVER/pcic_test -X -q -v ON_ERROR_STOP=1"
Q="psql $PGSERVER/pcic_test_load -X -q -v ON_ERROR_STOP=1"
D="psql $PGSERVER/pcic_test_days -X -q -v ON_ERROR_STOP=1"

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
export_run() {  # export_run <model> <period> <weekly 0|1> [days 0|1]
  $P -v model="$1" -v scenario=historical -v period="$2" -v weekly="$3" -v days="${4:-0}" -f sql/pcic_export.sql
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
$P -c "INSERT INTO pcic.series (model, scenario, year, crosswalk_md5) VALUES ('Ghost', 'historical', 2001, 'x')"
refused 'export: per-year days in pcic.series built on another crosswalk are refused' 'pcic.series were built on another crosswalk' export_run X 1981-2010 0
refused 'and so are they with DAYS=1 for another model' 'pcic.series were built on another crosswalk' export_run X 1981-2010 0 1
$P -c "DELETE FROM pcic.series WHERE model = 'Ghost'"
$P -c "INSERT INTO pcic.series (model, scenario, year, crosswalk_md5) VALUES ('PNWNAmet', 'historical', 2001, 'x')"
refused 'export: the run'"'"'s own model'"'"'s days on another crosswalk are refused without DAYS=1' 'pcic.series were built on another crosswalk' export_run PNWNAmet 1981-2010 1 0
succeeds 'and with DAYS=1 the export goes ahead' export_run PNWNAmet 1981-2010 1 1
check 'and deletes them, to be rebuilt' 0 "$($P -tA -c "SELECT count(*) FROM pcic.series")"
check 'the refused exports changed nothing' 'PNWNAmet 1951-2012, PNWNAmet 1981-2010' \
  "$($P -tA -c "SELECT string_agg(model || ' ' || period, ', ' ORDER BY period) FROM pcic.runs")"
# a per-year days catalogue on the runs' crosswalk, for the loads
$P -c "INSERT INTO pcic.series SELECT model, scenario, 2001, crosswalk_md5, 1460, 4, 10, 20, 300, 'abc1234', now() FROM pcic.runs WHERE period = '1981-2010'"

# ----------
# load the exported files into a second database
# ----------
ex() { $P -c "\\copy ($2) TO STDOUT WITH (FORMAT csv, HEADER)" | gzip > "$S/$1.csv.gz"; }
for t in runs day_bins fwa_crosswalk segment_weights series; do ex pcic.$t "SELECT * FROM pcic.$t"; done
for per in 1981-2010 1951-2012; do
  for t in subbasin_daily discharge_monthly discharge_weekly; do ex pcic.$t.pnwnamet_historical_$per "SELECT * FROM pcic.$t WHERE period = '$per'"; done
done
# load/pcic.sql, reading the files here instead of fresh-bc
local_load() {  # local_load <directory> <sql file to write>
  sed "s#curl -sSf https://fresh-bc.s3.us-west-2.amazonaws.com/fwapg/extras/\([^ ]*\) | gunzip#gunzip -c $1/\1#" ../../load/pcic.sql > "$2"
  if grep -q curl "$2" || [ "$(grep -c "gunzip -c $1/" "$2")" != 5 ]; then echo "load/pcic.sql has changed its fetch: fix local_load" >&2; exit 1; fi
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
for t in runs day_bins fwa_crosswalk segment_weights series subbasin_daily discharge_monthly discharge_weekly; do
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
for t in runs fwa_crosswalk segment_weights day_bins series; do
  gunzip -c "$S/pcic.$t.csv.gz" | awk -F, -v OFS=, '{ x = $1; $1 = $2; $2 = x; print }' | gzip > "$S/other/pcic.$t.csv.gz"
  refused "load: a pcic.$t file with reordered columns is refused" 'mismatch' $Q -f "$S/pcic_other.sql"
  cp "$S/pcic.$t.csv.gz" "$S/other/"
done
gunzip -c "$S/pcic.runs.csv.gz" | head -1 | gzip > "$S/other/pcic.runs.csv.gz"
refused 'load: a runs file with no runs is refused' 'lists no runs' $Q -f "$S/pcic_other.sql"
cp "$S/pcic.runs.csv.gz" "$S/other/"
gunzip -c "$S/pcic.series.csv.gz" | sed '2 s/^\([^,]*,[^,]*,[^,]*,\)[0-9a-f]*,/\1x,/' | gzip > "$S/other/pcic.series.csv.gz"
check 'the catalogue file was changed' 1 "$(gunzip -c "$S/other/pcic.series.csv.gz" | grep -c ',2001,x,' || true)"
refused 'load: a catalogue built on another crosswalk is refused' 'lists days built on another crosswalk' $Q -f "$S/pcic_other.sql"
# an empty catalogue loads, and keeps the catalogue already here, which is now a
# local one on the published crosswalk
gunzip -c "$S/pcic.series.csv.gz" | head -1 | gzip > "$S/other/pcic.series.csv.gz"
succeeds 'load: an empty catalogue loads' $Q -f "$S/pcic_other.sql"
check 'and keeps the catalogue built here on the same crosswalk' 1 "$($Q -tA -c "SELECT count(*) FROM pcic.series")"
$Q -c "UPDATE pcic.series SET crosswalk_md5 = 'x'"
refused 'load: a catalogue here on another crosswalk, not published, is refused' 'pcic.series were built on another crosswalk' $Q -f "$S/pcic_other.sql"
succeeds 'load: a published catalogue replaces the one here of its model and scenario' $Q -f "$S/pcic_local.sql"
check 'which then holds the published row' 1 "$($Q -tA -c "SELECT count(*) FROM pcic.series s, pcic.runs r WHERE s.crosswalk_md5 = r.crosswalk_md5 AND r.period = '1981-2010'")"
cp "$S/pcic.series.csv.gz" "$S/other/"
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

# ----------
# per-year days (fwapg#42): outlets 1 and 3 drain to 2 and 2 to 4 in PCIC's
# network, 5 to 3; 5 is unplaced and anchored to 3. On the FWA, 1 drains to 2, and
# 2 and 3 to 4 (3 joins below 2), so accumulated flow differs from PCIC's at 2.
# Two NetCDF files in hydromosaic's layout hold 2001-2003; an outlet's flow on a
# day is 10 * subid + month + day / 4 + (year - 2002) * subid / 2, so the
# years' mean is the climatology 10 * subid + month + day / 4
# ----------
DAYS_DB=$PGSERVER/pcic_test_days
$D -c "CREATE EXTENSION ltree" -c "CREATE SCHEMA fwapg"
$D -f ../../load/pcic_schema.sql
mkdir -p "$S/nc" "$S/daily" "$S/days" "$S/bad"
nc_write() {  # nc_write <file> <outlets, comma-separated> <first day> <last day> [fill day] [skipped day]
  uv run -q --with 'netCDF4>=1.6' --with 'numpy>=1.26' python - "$@" <<'PY'
import sys, numpy as np, netCDF4
path, outlets, first, last = sys.argv[1:5]
fill = np.datetime64(sys.argv[5]) if len(sys.argv) > 5 and sys.argv[5] else None
skip = np.datetime64(sys.argv[6]) if len(sys.argv) > 6 else None
ids = [int(x) for x in outlets.split(",")]
days = np.arange(np.datetime64(first), np.datetime64(last) + np.timedelta64(1, "D"))
if skip is not None:
    days = days[days != skip]
ds = netCDF4.Dataset(path, "w")
ds.createDimension("time", len(days)); ds.createDimension("outlet", len(ids))
t = ds.createVariable("time", "f8", ("time",)); t.units = "days since 1950-01-01 00:00:00"; t.calendar = "gregorian"
t[:] = (days - np.datetime64("1950-01-01")).astype(int)
b = ds.createVariable("basin_name", str, ("outlet",)); b[:] = np.array([str(i) for i in ids], dtype=object)
q = ds.createVariable("streamflow", "f8", ("time", "outlet"), fill_value=-9999.0)
y = days.astype("datetime64[Y]").astype(int) + 1970
m = days.astype("datetime64[M]").astype(int) % 12 + 1
d = (days - days.astype("datetime64[M]").astype("datetime64[D]")).astype(int) + 1
v = np.array([[10 * i + m[k] + d[k] / 4 + (y[k] - 2002) * i / 2 for i in ids] for k in range(len(days))])
if fill is not None:
    v[np.flatnonzero(days == fill)[0], 0] = -9999.0
q[:] = v
ds.close()
PY
}
nc_write "$S/nc/a.nc" 3,1,5 2001-01-01 2003-12-31
nc_write "$S/nc/b.nc" 4,2 2001-01-01 2003-12-31
nc_write "$S/bad/fill.nc" 4,2 2001-01-01 2003-12-31 2002-06-15
nc_write "$S/bad/gap.nc" 4,2 2001-01-01 2003-12-31 '' 2002-06-15
nc_write "$S/bad/gap2001.nc" 4,2 2001-01-01 2003-12-31 '' 2001-06-15
$D <<'SQL'
CREATE TABLE fwapg.pcic_outlets (subid integer PRIMARY KEY, dowsubid integer);
INSERT INTO fwapg.pcic_outlets VALUES (1, 2), (3, 2), (5, 3), (2, 4), (4, -1);
CREATE TABLE fwapg.pcic_subbasins (subid integer PRIMARY KEY, fwa_depth integer);
INSERT INTO fwapg.pcic_subbasins VALUES (4, 0), (2, 1), (3, 1), (1, 2);
CREATE TABLE fwapg.pcic_segment_weights (linear_feature_id bigint PRIMARY KEY, watershed_group_code text, subid integer, share double precision, upstream_subids integer[]);
-- 250, 260, 270 and 450 are mid-network: outlets above, not an outlet's segment.
-- 2's local flow is always negative: 260 clamps in every month, 270 in January
-- and, in 2002 and 2003, February
INSERT INTO fwapg.pcic_segment_weights VALUES
  (100, 'BULK', 1, 1, '{}'), (200, 'BULK', 2, 1, '{1}'), (250, 'BULK', 2, 0.5, '{1}'), (260, 'BULK', 2, 0.9, '{1}'), (270, 'BULK', 2, 0.61, '{1}'),
  (300, 'BULK', 3, 1, '{}'), (400, 'BULK', 4, 1, '{2,3}'), (450, 'BULK', 4, 0.3, '{2,3}');
SQL
sed -n '/^CREATE TABLE fwapg.pcic_fwa_crosswalk (/,/^);/p' sql/pcic_crosswalk04_select.sql | $D
$D -c "INSERT INTO fwapg.pcic_fwa_crosswalk (subid, dowsubid, anchor_subid, fwa_parent_subid, flag, linear_feature_id) VALUES
  (1, 2, 2, 2, NULL, 100), (2, 4, 4, 4, NULL, 200), (3, 2, 2, 4, NULL, 300), (4, -1, NULL, NULL, NULL, 400), (5, 3, 3, NULL, 'no_candidate', NULL)"

DMD5=$($D -tA -c "SELECT md5(string_agg(x::text, '|' ORDER BY x.subid)) FROM fwapg.pcic_fwa_crosswalk x")

# the job's climatology path (reduce_batch, taken from pcic_crosswalk.sh) for one
# year and for 2001-2003, against pcic_days.py rows
eval "$(sed -n '/^nc_outlets() {/,/^}/p; /^reduce_batch() {/,/^}/p' pcic_crosswalk.sh)"
check 'pcic_crosswalk.sh still defines nc_outlets and reduce_batch' 'nc_outlets reduce_batch' "$(declare -F nc_outlets reduce_batch | paste -sd' ' -)"
DAILY=$S/daily
for f in a b; do YEARS=2002/2002 NDAYS=365 reduce_batch "$S/nc/$f.nc" "$S/daily/$f.2002.csv"; done
for f in a b; do YEARS=2001/2003 NDAYS=1095 reduce_batch "$S/nc/$f.nc" "$S/daily/$f.csv"; done
$D -c "CREATE TABLE cdo_2002 (subid integer, month integer, day integer, q_m3s double precision)" \
  -c "CREATE TABLE py_2002 (LIKE cdo_2002)" \
  -c "CREATE TABLE fwapg.pcic_outlet_daily (subid integer, month integer, day integer, q_m3s double precision, PRIMARY KEY (subid, month, day))"
cat "$S"/daily/[ab].2002.csv | $D -c "\copy cdo_2002 FROM STDIN WITH (FORMAT csv)"
uv run -q --script pcic_days.py rows 2002 "$S/nc/a.nc" "$S/nc/b.nc" | $D -c "\copy py_2002 FROM STDIN WITH (FORMAT csv)"
cat "$S"/daily/[ab].csv | $D -c "\copy fwapg.pcic_outlet_daily FROM STDIN WITH (FORMAT csv)"
$D -v y1=2001 -v y2=2003 -f sql/pcic_crosswalk01_days.sql
checks 3 < <($D -tA <<'SQL'
SELECT 'pcic_days.py rows gives the cdo path''s values for a year, every outlet and day once',
  (SELECT count(*) FROM py_2002) = 5 * 365
  AND NOT EXISTS (SELECT * FROM py_2002 EXCEPT ALL SELECT * FROM cdo_2002)
  AND NOT EXISTS (SELECT * FROM cdo_2002 EXCEPT ALL SELECT * FROM py_2002);
SELECT 'and the values of the fixture''s formula',
  bool_and(q_m3s = 10 * subid + month + day / 4.0) FROM py_2002;
SELECT 'the cdo path''s climatology of 2001-2003 is the fixture''s, with no Feb 29',
  count(*) = 5 * 365 AND bool_and(abs(q_m3s - (10 * subid + month + day / 4.0)) < 1e-12) FROM fwapg.pcic_outlet_daily;
SQL
)
refused 'rows: a fill value in the year is refused' 'a fill or non-finite value in 2002' uv run -q --script pcic_days.py rows 2002 "$S/nc/a.nc" "$S/bad/fill.nc"
succeeds 'rows: a fill value in another year is not read' uv run -q --script pcic_days.py rows 2001 "$S/nc/a.nc" "$S/bad/fill.nc"
refused 'rows: a missing day is refused' '2002 has 364 days' uv run -q --script pcic_days.py rows 2002 "$S/nc/a.nc" "$S/bad/gap.nc"
refused 'rows: an outlet in two files is refused' 'in more than one place' uv run -q --script pcic_days.py rows 2002 "$S/nc/b.nc" "$S/bad/gap2001.nc"
refused 'rows: a year the files do not hold is refused' '2004 has 0 days' uv run -q --script pcic_days.py rows 2004 "$S/nc/a.nc"

# sql/pcic_crosswalk06_daily.sql on the climatology, against the flows by hand: with
# c(o) the outlet's climatology, local runoff is c1 at 1, c3 - c5 + c5 at 3 (5's
# runoff joins its anchor), c2 - c1 - c3 at 2 and c4 - c2 at 4; accumulated on the
# FWA it is c1, c2 - c3, c3 and c4
$D -v src=pcic_outlet_daily -v dst=pcic_subbasins_daily -f sql/pcic_crosswalk06_daily.sql
checks 2 < <($D -tA <<'SQL'
WITH c AS (SELECT month, day, subid, 10 * subid + month + day / 4.0 AS c FROM fwapg.pcic_outlet_daily),
w AS (
  SELECT month, day,
    max(c) FILTER (WHERE subid = 1) AS c1, max(c) FILTER (WHERE subid = 2) AS c2,
    max(c) FILTER (WHERE subid = 3) AS c3, max(c) FILTER (WHERE subid = 4) AS c4
  FROM c GROUP BY month, day
),
want AS (
  SELECT month, day, 1 AS subid, c1 AS q_local, c1 AS q_acc FROM w
  UNION ALL SELECT month, day, 2, c2 - c1 - c3, c2 - c3 FROM w
  UNION ALL SELECT month, day, 3, c3, c3 FROM w
  UNION ALL SELECT month, day, 4, c4 - c2, c4 FROM w
)
SELECT '06_daily: local and accumulated flow per sub-basin and day, by hand',
  count(*) = 4 * 365 AND (SELECT count(*) FROM fwapg.pcic_subbasins_daily) = 4 * 365
  AND max(abs(s.q_local - w.q_local)) < 1e-9 AND max(abs(s.q_acc - w.q_acc)) < 1e-9
FROM fwapg.pcic_subbasins_daily s INNER JOIN want w USING (subid, month, day);
SELECT '06_daily: on the FWA, 2 does not carry 3''s flow as PCIC''s outflow does',
  bool_and(abs(s.q_acc - o.q_m3s) > 1)
FROM fwapg.pcic_subbasins_daily s INNER JOIN fwapg.pcic_outlet_daily o USING (subid, month, day) WHERE s.subid = 2;
SQL
)
$D -v step=month -v table=monthly -f sql/pcic_crosswalk08_periods.sql

# the per-year files, built by days_build.sh as the job builds them
$D -c "CREATE TABLE fwapg.pcic_subbasins_months (year integer, subid integer, month integer, q_local double precision, q_acc double precision, PRIMARY KEY (year, subid, month))"
for y in 2001 2002 2003; do
  succeeds "days_build.sh builds $y" env DATABASE_URL="$DAYS_DB" ./days_build.sh $y "$S/days/pcic.subbasin_days.Test_historical.$y.parquet" "$DMD5" abc1234 "$S/nc/a.nc" "$S/nc/b.nc"
done
# each year's file against the flows by hand: as for the climatology, with each
# outlet's flow that year, q(o) = c(o) + (year - 2002) * o / 2, rounded to float32
for y in 2001 2002 2003; do uv run -q --script pcic_days.py dump "$S/days/pcic.subbasin_days.Test_historical.$y.parquet"; done \
  | $D -c "CREATE TABLE dumped (subid integer, date date, q_local double precision, q_acc double precision)" -c "\copy dumped FROM STDIN WITH (FORMAT csv)"
fp=$(uv run -q --script pcic_days.py fingerprint "$S/days/pcic.subbasin_days.Test_historical.2003.parquet")
$D <<'SQL'
CREATE TABLE days_want AS
WITH d AS (SELECT g::date AS date FROM generate_series('2001-01-01'::date, '2003-12-31'::date, interval '1 day') g),
q AS (
  SELECT date, o, 10 * o + extract(month FROM date) + extract(day FROM date) / 4.0 + (extract(year FROM date) - 2002) * o / 2.0 AS q
  FROM d, generate_series(1, 4) o
),
w AS (
  SELECT date, max(q) FILTER (WHERE o = 1) AS q1, max(q) FILTER (WHERE o = 2) AS q2,
    max(q) FILTER (WHERE o = 3) AS q3, max(q) FILTER (WHERE o = 4) AS q4
  FROM q GROUP BY date
)
SELECT 1 AS subid, date, q1::real::float8 AS q_local, q1::real::float8 AS q_acc FROM w
UNION ALL SELECT 2, date, (q2 - q1 - q3)::real::float8, (q2 - q3)::real::float8 FROM w
UNION ALL SELECT 3, date, q3::real::float8, q3::real::float8 FROM w
UNION ALL SELECT 4, date, (q4 - q2)::real::float8, q4::real::float8 FROM w;
SQL
checks 3 < <($D -tA <<SQL
SELECT 'each year''s file holds its flows by hand, at float32, one row per sub-basin and real date',
  (SELECT count(*) FROM dumped) = 4 * 1095
  AND NOT EXISTS (SELECT * FROM dumped EXCEPT ALL SELECT * FROM days_want)
  AND NOT EXISTS (SELECT * FROM days_want EXCEPT ALL SELECT * FROM dumped);
SELECT 'a file''s catalogue line is its fingerprint, by the formula in SQL',
  '$fp' = format('2003,%s,%s,%s,%s,%s,$DMD5,abc1234', count(*), count(DISTINCT subid),
    sum(floor(q_local::real::float8 * 1000 + 0.5))::bigint, sum(floor(q_acc::real::float8 * 1000 + 0.5))::bigint,
    $(wc -c < "$S/days/pcic.subbasin_days.Test_historical.2003.parquet" | tr -d ' '))
FROM days_want WHERE extract(year FROM date) = 2003;
SELECT 'the years'' monthly means are kept, and the years'' own tables dropped',
  (SELECT count(*) FROM fwapg.pcic_subbasins_months) = 3 * 4 * 12
  AND NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'fwapg' AND tablename ~ '_year_');
SQL
)
cp "$S/days/pcic.subbasin_days.Test_historical.2002.parquet" "$S/bad/pcic.subbasin_days.Test_historical.2001.parquet"
refused 'fingerprint: a file named for another year is refused' 'holds the days of 2002' uv run -q --script pcic_days.py fingerprint "$S/bad/pcic.subbasin_days.Test_historical.2001.parquet"
# a year's rows as days_build.sh writes them, from a file; awk changes them
rewrite() {  # rewrite <year> <out> <awk program>
  uv run -q --script pcic_days.py dump "$S/days/pcic.subbasin_days.Test_historical.$1.parquet" \
    | awk -F, -v OFS=, '{ split($2, d, "-"); $2 = (d[2] + 0) "," (d[3] + 0) } '"$3"' { print }' \
    | uv run -q --script pcic_days.py parquet "$1" "$2" "$DMD5" abc1234
}
refused 'parquet: a sub-basin without every day of the year is refused' 'not every day of 2003' rewrite 2003 "$S/bad/short.parquet" '$2 == "6,15" && $1 == 2 { next }'
succeeds 'parquet: a file rewritten unchanged is accepted' rewrite 2003 "$S/bad/same.parquet" ''
check 'and holds the same rows' "$(uv run -q --script pcic_days.py fingerprint "$S/days/pcic.subbasin_days.Test_historical.2003.parquet" | cut -d, -f1-5)" \
  "$(uv run -q --script pcic_days.py fingerprint "$S/bad/same.parquet" | cut -d, -f1-5)"
check 'a file names the crosswalk and commit it was built from' "$DMD5,abc1234" "$(uv run -q --script pcic_days.py meta "$S/bad/same.parquet")"
uv run -q --with 'pyarrow>=15' python -c "import sys, pyarrow.parquet as pq; pq.write_table(pq.read_table(sys.argv[1]).replace_schema_metadata(None), sys.argv[2])" "$S/bad/same.parquet" "$S/bad/pcic.subbasin_days.Test_historical.2003.parquet"
refused 'fingerprint: a file that does not name its crosswalk and commit is refused' 'does not name the crosswalk' uv run -q --script pcic_days.py fingerprint "$S/bad/pcic.subbasin_days.Test_historical.2003.parquet"
refused 'parquet: a crosswalk that is not an md5 is refused' 'not an md5' sh -c 'echo 1,1,1,1,1 | uv run -q --script pcic_days.py parquet 2003 "$1/x.parquet" abc abc1234' _ "$S/bad"

# sql/qa_days.sql over the files, and over the files with one year changed
days_means() {  # days_means <directory>
  $D -c "DROP TABLE IF EXISTS fwapg.pcic_days_means" \
    -c "CREATE TABLE fwapg.pcic_days_means (subid integer, month integer, day integer, q_local double precision, q_acc double precision, abs_local double precision, abs_acc double precision, n integer, PRIMARY KEY (subid, month, day))"
  uv run -q --script pcic_days.py means 2001 2003 "$1"/*.parquet | $D -c "\copy fwapg.pcic_days_means FROM STDIN WITH (FORMAT csv)"
}
days_means "$S/days"
check 'qa_days.sql passes on the files' 't t t t' "$($D -tA -v ran_all=1 -v y1=2001 -v y2=2003 -f sql/qa_days.sql | cut -d'|' -f2 | paste -sd' ' -)"
check 'and checks the files alone when some years were not built here' 't t t' "$($D -tA -v ran_all=0 -v y1=2001 -v y2=2003 -f sql/qa_days.sql | cut -d'|' -f2 | paste -sd' ' -)"
mkdir "$S/perturbed"
cp "$S"/days/*.2001.parquet "$S"/days/*.2002.parquet "$S/perturbed/"
rewrite 2003 "$S/perturbed/pcic.subbasin_days.Test_historical.2003.parquet" '$1 == 2 && $2 == "6,15" { $3 = $3 + 0.001 }'
days_means "$S/perturbed"
check 'qa_days.sql fails when one value of one year''s file is off by 1 L/s' 'f t' "$($D -tA -v ran_all=0 -v y1=2001 -v y2=2003 -f sql/qa_days.sql | cut -d'|' -f2 | sed -n '2,3p' | paste -sd' ' -)"
rm "$S/perturbed/pcic.subbasin_days.Test_historical.2003.parquet"
days_means "$S/perturbed"
check 'qa_days.sql fails when a year''s file is missing' 'f' "$($D -tA -v ran_all=0 -v y1=2001 -v y2=2003 -f sql/qa_days.sql | cut -d'|' -f2 | head -1)"
days_means "$S/days"

# sql/qa_report_days.sql's clamp count against 09's formula on every mid-network
# segment, year and month
$D -c "CREATE TABLE fwapg.pcic_discharge_monthly (linear_feature_id bigint, watershed_group_code text, month integer, q_raw double precision, q_m3s double precision, PRIMARY KEY (linear_feature_id, month))"
$D -v wsg=BULK -v step=month -v table=monthly -f sql/pcic_crosswalk09_discharge.sql
want=$($D -tA <<'SQL'
WITH flows AS (
  SELECT year, subid, month, q_local, q_acc FROM fwapg.pcic_subbasins_months
  UNION ALL SELECT NULL, subid, month, q_local, q_acc FROM fwapg.pcic_subbasins_monthly
)
SELECT coalesce(m.year::text, 'climatology') || ':' || count(*) FILTER (WHERE
  coalesce((SELECT sum(u.q_acc) FROM flows u WHERE u.subid = ANY(w.upstream_subids) AND u.month = m.month AND u.year IS NOT DISTINCT FROM m.year), 0)
  + m.q_local * w.share < 0)
FROM fwapg.pcic_segment_weights w
INNER JOIN flows m ON m.subid = w.subid
WHERE w.linear_feature_id IN (250, 260, 270, 450)
GROUP BY m.year ORDER BY m.year NULLS FIRST
SQL
)
got=$($D -tA -f sql/qa_report_days.sql | awk -F'|' '$1 ~ /^([0-9]{4}|climatology)$/ { print $1 ":" $2 }')
check 'qa_report_days.sql counts the clamped mid-network segment-months of every year, as 09 would' "$want" "$got"
check 'the fixture clamps 13, 14 and 14 segment-months in its years, 14 in the climatology' 'climatology:14 2001:13 2002:14 2003:14' "$(paste -sd' ' - <<< "$want")"
check 'and its climatology count is 09''s own' "$($D -tA -c "SELECT count(*) FROM fwapg.pcic_discharge_monthly WHERE linear_feature_id IN (250, 260, 270, 450) AND q_raw < 0")" \
  "$(grep '^climatology:' <<< "$got" | cut -d: -f2)"

# the catalogue: sql/pcic_export_days.sql and its refusals
$D -c "INSERT INTO pcic.fwa_crosswalk SELECT * FROM fwapg.pcic_fwa_crosswalk" \
  -c "INSERT INTO pcic.runs (model, scenario, period, crosswalk_md5) SELECT 'Test', 'historical', '2001-2003', md5(string_agg(x::text, '|' ORDER BY x.subid)) FROM pcic.fwa_crosswalk x" \
  -c "CREATE TABLE fwapg.pcic_series_files (year integer, rows bigint, subbasins bigint, q_local_sum bigint, q_acc_sum bigint, bytes bigint, crosswalk_md5 text, commit text)"
uv run -q --script pcic_days.py fingerprint "$S"/days/*.parquet | $D -c "\copy fwapg.pcic_series_files FROM STDIN WITH (FORMAT csv)"
export_days() {  # export_days <years>
  $D -v model=Test -v scenario=historical -v years="$1" -f sql/pcic_export_days.sql
}
succeeds 'export the catalogue of 2001-2003' export_days 2001,2002,2003
check 'the catalogue lists each file, with the crosswalk and commit' '2001|1460|4|abc1234 2002|1460|4|abc1234 2003|1460|4|abc1234' \
  "$($D -tA -c "SELECT year, rows, subbasins, commit FROM pcic.series s, pcic.runs r WHERE s.crosswalk_md5 = r.crosswalk_md5 ORDER BY year" | paste -sd' ' -)"
refused 'export_days: a year of the series with no file is refused' 'years 2004 of the series have no file' export_days 2001,2002,2003,2004
refused 'export_days: a file of a year outside the series is refused' 'files of years 2003 are not of the series' export_days 2001,2002
$D -c "UPDATE fwapg.pcic_series_files SET rows = rows + 1 WHERE year = 2002"
refused 'export_days: a file short of a row per sub-basin and day is refused' 'files of years 2002 do not hold' export_days 2001,2002,2003
$D -c "UPDATE fwapg.pcic_series_files SET rows = rows - 1 WHERE year = 2002" -c "UPDATE fwapg.pcic_series_files SET subbasins = 3, rows = 3 * 365 WHERE year = 2002"
refused 'export_days: a file of other sub-basins than the placed outlets is refused' 'files of years 2002 do not hold' export_days 2001,2002,2003
$D -c "UPDATE fwapg.pcic_series_files SET subbasins = 4, rows = 4 * 365 WHERE year = 2002" -c "UPDATE fwapg.pcic_series_files SET crosswalk_md5 = 'x' WHERE year = 2001"
refused 'export_days: a file routed on another crosswalk is refused' 'files of years 2001 were routed on another crosswalk' export_days 2001,2002,2003
$D -c "UPDATE fwapg.pcic_series_files SET crosswalk_md5 = '$DMD5'" -c "UPDATE pcic.runs SET crosswalk_md5 = 'x'"
refused 'export_days: a crosswalk unlike the runs'"'"' is refused' 'is not the crosswalk runs' export_days 2001,2002,2003
$D -c "DELETE FROM pcic.runs"
refused 'export_days: no published run is refused' 'lists no run' export_days 2001,2002,2003
check 'the refused exports changed nothing' 3 "$($D -tA -c "SELECT count(*) FROM pcic.series WHERE commit = 'abc1234'")"

finished=1
[ "$fails" -eq 0 ] && echo 'all pcic tests pass' || { echo "$fails failed"; exit 1; }
