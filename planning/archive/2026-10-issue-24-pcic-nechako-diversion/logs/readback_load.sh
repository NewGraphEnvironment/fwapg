#!/bin/bash
# #24: load the published PCIC files from fresh-bc into a new scratch database the way
# load.sh does (schema, shared tables, then each run's sub-basin days and monthly flow),
# and check the loaded crosswalk and runs. ADMIN_URL is a server connection that may
# create databases; the scratch database is dropped at the end.
#
#   ADMIN_URL=... ./readback_load.sh > 20261027_readback_load.out 2>&1
set -euo pipefail

: "${ADMIN_URL:?a server connection that may create databases}"
REPO=$(cd "$(dirname "$0")/../../../.." && pwd)
DB=pcic_readback24
SCRATCH="${ADMIN_URL%/*}/$DB"
trap 'psql "$ADMIN_URL" -q -c "DROP DATABASE IF EXISTS $DB"' EXIT

psql "$ADMIN_URL" -q -c "DROP DATABASE IF EXISTS $DB" -c "CREATE DATABASE $DB"
PSQL="psql $SCRATCH -v ON_ERROR_STOP=1 -q"
$PSQL -c "CREATE EXTENSION ltree"
cd "$REPO"
echo "== load/pcic_schema.sql, load/pcic.sql $(date -u +%H:%M:%SZ)"
$PSQL -f load/pcic_schema.sql
$PSQL -f load/pcic.sql
for run in pnwnamet_historical_1951-2012 pnwnamet_historical_1981-2010; do
  for table in subbasin_daily discharge_monthly; do
    echo "== pcic.$table $run $(date -u +%H:%M:%SZ)"
    curl -sSf "https://fresh-bc.s3.us-west-2.amazonaws.com/fwapg/extras/pcic.$table.$run.csv.gz" \
      | gunzip | $PSQL -v table=$table -f load/pcic_run.sql
  done
done
echo "== loaded $(date -u +%H:%M:%SZ)"
psql "$SCRATCH" -X -v ON_ERROR_STOP=1 <<'SQL'
\pset footer off
SELECT md5(string_agg(x::text, '|' ORDER BY x.subid)) AS crosswalk_md5, count(*) AS outlets FROM pcic.fwa_crosswalk x;
SELECT period, crosswalk_md5, daily_rows, monthly_rows, weekly_rows FROM pcic.runs ORDER BY period;
SELECT count(*) AS series_years, min(year), max(year), count(DISTINCT crosswalk_md5) AS crosswalks FROM pcic.series;
SELECT subid, fwa_parent_subid, linear_feature_id, round(downstream_route_measure::numeric, 1) AS measure
FROM pcic.fwa_crosswalk WHERE subid = 1007550;
SELECT period, round(avg(q_m3s)::numeric, 3) AS knewstubb_exit_q
FROM pcic.discharge_monthly WHERE linear_feature_id = 701799415 GROUP BY 1 ORDER BY 1;
SQL
echo "== done $(date -u +%H:%M:%SZ)"
