#!/bin/bash
# #25: the pcic export guards and the load checks, on synthetic staging tables in
# two scratch databases (fwapg_t25, fwapg_t25b) on the server in $PGSERVER
# (e.g. postgresql://postgres:postgres@localhost:5432). Run from the repo root.
# Prints each refusal; every "ERROR" line below a "---" heading is expected.
set -uo pipefail
S=$(mktemp -d)
T=$PGSERVER/fwapg_t25; B=$PGSERVER/fwapg_t25b
psql "$PGSERVER/postgres" -X -q -c "DROP DATABASE IF EXISTS fwapg_t25" -c "CREATE DATABASE fwapg_t25" -c "DROP DATABASE IF EXISTS fwapg_t25b" -c "CREATE DATABASE fwapg_t25b"
P="psql $T -X -q -v ON_ERROR_STOP=1"
$P -c "CREATE EXTENSION ltree" -c "CREATE SCHEMA fwapg"
sed -n '/^CREATE TABLE fwapg.pcic_fwa_crosswalk (/,/^);/p' extras/pcic_crosswalk/sql/pcic_crosswalk04_select.sql | $P
$P -v y1=1981 -v y2=2010 -f extras/pcic_crosswalk/sql/pcic_crosswalk01_days.sql
$P <<'SQL'
INSERT INTO fwapg.pcic_fwa_crosswalk (subid, dowsubid, flag, linear_feature_id) VALUES (1, 2, NULL, 100), (2, -1, NULL, 200);
CREATE TABLE fwapg.pcic_segment_weights (linear_feature_id bigint PRIMARY KEY, watershed_group_code text, subid integer, share double precision, upstream_subids integer[]);
INSERT INTO fwapg.pcic_segment_weights VALUES (100, 'BULK', 1, 1, '{}'), (150, 'BULK', 2, 0.25, '{1}'), (200, 'BULK', 2, 1, '{1}');
CREATE TABLE fwapg.pcic_subbasins_daily AS
SELECT s.subid, b.month, b.day, s.subid * 1.5 + b.month AS q_local, s.subid * 3.0 + b.month AS q_acc
FROM (VALUES (1), (2)) s(subid), fwapg.pcic_day_bins b WHERE b.n_days > 0;
CREATE TABLE fwapg.pcic_discharge_monthly AS SELECT w.linear_feature_id, w.watershed_group_code, m.month, 0::float8 AS q_raw, (w.linear_feature_id + m.month)::float8 AS q_m3s FROM fwapg.pcic_segment_weights w, generate_series(1,12) m(month);
CREATE TABLE fwapg.pcic_discharge_weekly AS SELECT w.linear_feature_id, w.watershed_group_code, k.week, 0::float8 AS q_raw, (w.linear_feature_id + k.week / 7.0)::float8 AS q_m3s FROM fwapg.pcic_segment_weights w, generate_series(1,52) k(week);
SQL
$P -f load/pcic_schema.sql
exp() { $P -v model="$1" -v scenario=historical -v period="$2" -v weekly="$3" -f extras/pcic_crosswalk/sql/pcic_export.sql 2>&1 | grep -o 'ERROR.*' | cut -c1-160; }
exp PNWNAmet 1981-2010 1
$P -c "UPDATE fwapg.pcic_discharge_monthly SET q_m3s = q_m3s * 2"
exp PNWNAmet 1951-2012 0
echo "--- changed crosswalk (refused):"; $P -c "UPDATE fwapg.pcic_fwa_crosswalk SET flag = 'demoted' WHERE subid = 2"; exp X 1981-2010 0; $P -c "UPDATE fwapg.pcic_fwa_crosswalk SET flag = NULL WHERE subid = 2"
echo "--- changed weights (refused):"; $P -c "UPDATE fwapg.pcic_segment_weights SET share = 0.5 WHERE linear_feature_id = 150"; exp X 1981-2010 0; $P -c "UPDATE fwapg.pcic_segment_weights SET share = 0.25 WHERE linear_feature_id = 150"
echo "--- orphan rows (refused):"; $P -c "INSERT INTO pcic.discharge_monthly VALUES ('Ghost','historical','2000-2001',100,'BULK',1,1.0)"; exp X 1981-2010 0; $P -c "DELETE FROM pcic.discharge_monthly WHERE model='Ghost'"
echo "--- runs after the guards (expect the two PNWNAmet runs):"; $P -tA -c "select string_agg(model||' '||period, ', ' order by period) from pcic.runs"
ex() { $P -c "\\copy ($2) TO STDOUT WITH (FORMAT csv, HEADER)" | gzip > "$S/$1.csv.gz"; }
ex pcic.runs "SELECT * FROM pcic.runs"; ex pcic.day_bins "SELECT * FROM pcic.day_bins"
ex pcic.fwa_crosswalk "SELECT * FROM pcic.fwa_crosswalk"; ex pcic.segment_weights "SELECT * FROM pcic.segment_weights"
for per in 1981-2010 1951-2012; do for t in subbasin_daily discharge_monthly; do ex pcic.$t.pnwnamet_historical_$per "SELECT * FROM pcic.$t WHERE period = '$per'"; done; done
ex pcic.discharge_weekly.pnwnamet_historical_1981-2010 "SELECT * FROM pcic.discharge_weekly"
sed "s#curl -sSf https://fresh-bc.s3.us-west-2.amazonaws.com/fwapg/extras/\([^ ]*\) | gunzip#gunzip -c $S/\1#" load/pcic.sql > "$S/pcic_local.sql"
Q="psql $B -X -q -v ON_ERROR_STOP=1"
$Q -c "CREATE EXTENSION ltree"; $Q -f load/pcic_schema.sql; $Q -f "$S/pcic_local.sql"
for per in 1951-2012 1981-2010; do for t in subbasin_daily discharge_monthly; do gunzip -c "$S/pcic.$t.pnwnamet_historical_$per.csv.gz" | $Q -v table=$t -f load/pcic_run.sql; done; done
gunzip -c "$S/pcic.discharge_weekly.pnwnamet_historical_1981-2010.csv.gz" | $Q -v table=discharge_weekly -f load/pcic_run.sql
echo "--- loaded (expect 2|1464|72|156|3):"; $Q -tA -c "select (select count(*) from pcic.runs), (select count(*) from pcic.subbasin_daily), (select count(*) from pcic.discharge_monthly), (select count(*) from pcic.discharge_weekly), (select count(*) from pcic.segment_weights)"
m=$S/pcic.discharge_monthly.pnwnamet_historical_1981-2010.csv.gz
echo "--- truncated file (refused):"; gunzip -c "$m" | head -20 | $Q -v table=discharge_monthly -f load/pcic_run.sql 2>&1 | grep -o 'ERROR.*' | cut -c1-150
echo "--- reordered columns (refused):"; gunzip -c "$m" | awk -F, -v OFS=, '{t=$6; $6=$7; $7=t; print}' | $Q -v table=discharge_monthly -f load/pcic_run.sql 2>&1 | grep -o 'ERROR.*' | cut -c1-120
echo "--- run not in pcic.runs (refused):"; gunzip -c "$m" | sed 's/1981-2010/1971-2000/' | $Q -v table=discharge_monthly -f load/pcic_run.sql 2>&1 | grep -o 'ERROR.*' | cut -c1-120
echo "--- stale published rows dropped on reload (expect 1981-2010 monthly 0, daily 732, weekly 156):"
$Q -c "UPDATE pcic.runs SET monthly_q_sum = monthly_q_sum + 1 WHERE period = '1981-2010'"; $Q -f "$S/pcic_local.sql"
$Q -tA -c "select period, (select count(*) from pcic.subbasin_daily d where d.period=r.period), (select count(*) from pcic.discharge_monthly d where d.period=r.period), (select count(*) from pcic.discharge_weekly d where d.period=r.period) from pcic.runs r order by period"
echo "--- orphan on reload (refused):"; $Q -c "INSERT INTO pcic.discharge_weekly VALUES ('Ghost','h','2000-2001',1,'X',1,1)"; $Q -f "$S/pcic_local.sql" 2>&1 | grep -o 'ERROR.*' | cut -c1-140
psql "$PGSERVER/postgres" -X -q -c "DROP DATABASE fwapg_t25" -c "DROP DATABASE fwapg_t25b"
rm -rf "$S"
