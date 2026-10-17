#!/bin/bash
# Phase 2 regression (#25): monthly means derived from a run's daily climatology
# cache, each calendar day weighted by its count in YEARS, against the cached
# cdo ymonmean output of the first build (data/monthly/*.csv, 1951-2012).
# Run from extras/pcic_crosswalk with DATABASE_URL set. Writes only fwapg.t25_* tables, then drops them.
set -euo pipefail
PSQL="psql $DATABASE_URL -v ON_ERROR_STOP=1 -X -q"
DAILY=data/daily/pnwnamet_historical_1951-2012
$PSQL -c "DROP TABLE IF EXISTS fwapg.t25_daily, fwapg.t25_ref, fwapg.t25_bins"
$PSQL -c "CREATE TABLE fwapg.t25_daily (subid integer, month integer, day integer, q_m3s double precision)"
cat "$DAILY"/*.csv | $PSQL -c "\copy fwapg.t25_daily FROM STDIN WITH (FORMAT csv)"
$PSQL -c "CREATE TABLE fwapg.t25_ref (subid integer, month integer, q_m3s double precision)"
cat data/monthly/*.csv | $PSQL -c "\copy fwapg.t25_ref FROM STDIN WITH (FORMAT csv)"
$PSQL -c "CREATE TABLE fwapg.t25_bins AS
  SELECT extract(month FROM d)::int AS month, extract(day FROM d)::int AS day, count(*) AS n_days
  FROM generate_series('1951-01-01'::date, '2012-12-31'::date, interval '1 day') d GROUP BY 1, 2"
psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
WITH derived AS (
  SELECT q.subid, q.month, sum(q.q_m3s * b.n_days) / sum(b.n_days) AS q
  FROM fwapg.t25_daily q JOIN fwapg.t25_bins b USING (month, day)
  GROUP BY q.subid, q.month
)
SELECT
  (SELECT count(*) FROM fwapg.t25_ref) AS ref_rows,
  (SELECT count(*) FROM derived) AS derived_rows,
  count(*) FILTER (WHERE r.subid IS NULL OR d.subid IS NULL) AS keys_unmatched,
  count(*) FILTER (WHERE abs(d.q - r.q_m3s) > 1e-9 + 1e-12 * abs(r.q_m3s)) AS over_tolerance,
  max(abs(d.q - r.q_m3s)) AS max_abs_diff,
  max(abs(d.q - r.q_m3s) / nullif(abs(r.q_m3s), 0)) AS max_rel_diff
FROM derived d FULL JOIN fwapg.t25_ref r USING (subid, month);
SQL
cmp <(sort data/series/missing.txt) <(sort "data/series/pnwnamet_historical_1951-2012/missing.txt") && echo "missing.txt identical"
$PSQL -c "DROP TABLE fwapg.t25_daily, fwapg.t25_ref, fwapg.t25_bins"
