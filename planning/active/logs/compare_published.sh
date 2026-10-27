#!/bin/bash
# #24: what the diversion changed outside the Nechako Reservoir. Loads the published
# (old) crosswalk, weights and one run's sub-basin days from fresh-bc, and the rebuilt
# files from $NEW (the build's directory), into a scratch schema, and compares them,
# split by whether an outlet is in 1007550's PCIC subtree (itself and every outlet
# whose dowsubid chain reaches it) and whether a segment is in the five groups.
#
#   DATABASE_URL=... NEW=<build dir> RUN=pnwnamet_historical_1981-2010 ./compare_published.sh
set -euo pipefail

: "${NEW:?the directory holding the rebuilt pcic.*.csv.gz}" "${RUN:?the run of the sub-basin days to compare}"
URL=https://fresh-bc.s3.us-west-2.amazonaws.com/fwapg/extras
PSQL="psql $DATABASE_URL -v ON_ERROR_STOP=1 -q"
trap '$PSQL -c "DROP SCHEMA IF EXISTS cmp24 CASCADE"' EXIT

$PSQL -c "DROP SCHEMA IF EXISTS cmp24 CASCADE" -c "CREATE SCHEMA cmp24"
for t in fwa_crosswalk segment_weights subbasin_daily; do
  for side in old new; do
    $PSQL -c "CREATE TABLE cmp24.${t}_$side (LIKE pcic.$t)"
  done
done
load() {  # table side source
  if [ "$2" = old ]; then curl -sSf "$URL/$3"; else cat "$NEW/$3"; fi \
    | gunzip | $PSQL -c "\copy cmp24.$1_$2 FROM STDIN WITH (FORMAT csv, HEADER MATCH)"
}
for side in old new; do
  load fwa_crosswalk $side pcic.fwa_crosswalk.csv.gz
  load segment_weights $side pcic.segment_weights.csv.gz
  load subbasin_daily $side "pcic.subbasin_daily.$RUN.csv.gz"
done
echo "== loaded $(date -u +%H:%M:%SZ)"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -X <<'SQL'
\pset footer off
CREATE TABLE cmp24.subtree AS
WITH RECURSIVE t AS (
  SELECT 1007550 AS subid
  UNION ALL
  SELECT x.subid FROM cmp24.fwa_crosswalk_new x JOIN t ON x.dowsubid = t.subid
)
SELECT subid FROM t;
SELECT count(*) AS subtree_outlets FROM cmp24.subtree;

\echo == crosswalk rows that differ, inside and outside the subtree
SELECT (s.subid IS NOT NULL) AS in_subtree, count(*) AS rows_differ
FROM cmp24.fwa_crosswalk_old o
FULL JOIN cmp24.fwa_crosswalk_new n USING (subid)
LEFT JOIN cmp24.subtree s USING (subid)
WHERE (o.*) IS DISTINCT FROM (n.*)
GROUP BY 1 ORDER BY 1;
\echo == of them, outside the subtree
SELECT subid, o.fwa_parent_subid AS old_parent, n.fwa_parent_subid AS new_parent, o.flag AS old_flag, n.flag AS new_flag
FROM cmp24.fwa_crosswalk_old o
FULL JOIN cmp24.fwa_crosswalk_new n USING (subid)
WHERE (o.*) IS DISTINCT FROM (n.*)
AND subid NOT IN (SELECT subid FROM cmp24.subtree)
ORDER BY subid LIMIT 20;

\echo == weights that differ, by group (any column; share beyond 1e-9)
SELECT coalesce(n.watershed_group_code, o.watershed_group_code) AS wsg, count(*) AS segments_differ
FROM cmp24.segment_weights_old o
FULL JOIN cmp24.segment_weights_new n USING (linear_feature_id)
WHERE o.linear_feature_id IS NULL OR n.linear_feature_id IS NULL
OR o.subid IS DISTINCT FROM n.subid
OR o.upstream_subids IS DISTINCT FROM n.upstream_subids
OR abs(o.share - n.share) > 1e-9 OR (o.share IS NULL) <> (n.share IS NULL)
GROUP BY 1 ORDER BY 1;

\echo == weights that differ, by kind: outside the five groups, and in them
WITH d AS (
  SELECT coalesce(n.watershed_group_code, o.watershed_group_code) IN ('LEUT', 'UEUT', 'UNRS', 'LNRS', 'CHES') AS nechako_groups,
    o.linear_feature_id IS NULL OR n.linear_feature_id IS NULL AS missing,
    o.subid IS DISTINCT FROM n.subid AS subid_differs,
    abs(o.share - n.share) > 1e-9 AS share_differs,
    (SELECT array_agg(u ORDER BY u) FROM unnest(o.upstream_subids) u)
      IS DISTINCT FROM (SELECT array_agg(u ORDER BY u) FROM unnest(n.upstream_subids) u) AS set_differs,
    o.upstream_subids IS DISTINCT FROM n.upstream_subids AS array_differs
  FROM cmp24.segment_weights_old o
  FULL JOIN cmp24.segment_weights_new n USING (linear_feature_id)
)
SELECT nechako_groups, count(*) FILTER (WHERE missing) AS missing,
  count(*) FILTER (WHERE subid_differs) AS subid_differs,
  count(*) FILTER (WHERE share_differs) AS share_differs,
  count(*) FILTER (WHERE set_differs) AS upstream_set_differs,
  count(*) FILTER (WHERE array_differs AND NOT set_differs) AS order_only
FROM d
WHERE missing OR subid_differs OR share_differs OR array_differs
GROUP BY 1 ORDER BY 1;

\echo == sub-basin days: rows that differ by more than 1e-9 m3/s, inside and outside the subtree
SELECT (s.subid IS NOT NULL) AS in_subtree, count(*) AS rows_differ,
  count(DISTINCT coalesce(n.subid, o.subid)) AS subids
FROM cmp24.subbasin_daily_old o
FULL JOIN cmp24.subbasin_daily_new n USING (model, scenario, period, subid, month, day)
LEFT JOIN cmp24.subtree s ON s.subid = coalesce(n.subid, o.subid)
WHERE o.subid IS NULL OR n.subid IS NULL
OR o.n_days IS DISTINCT FROM n.n_days
OR abs(o.q_local - n.q_local) > 1e-9 OR abs(o.q_acc - n.q_acc) > 1e-9
GROUP BY 1 ORDER BY 1;
\echo == of them, outside the subtree
SELECT coalesce(n.subid, o.subid) AS subid, count(*) AS days,
  round(max(abs(o.q_local - n.q_local))::numeric, 6) AS max_dq_local,
  round(max(abs(o.q_acc - n.q_acc))::numeric, 6) AS max_dq_acc
FROM cmp24.subbasin_daily_old o
FULL JOIN cmp24.subbasin_daily_new n USING (model, scenario, period, subid, month, day)
WHERE coalesce(n.subid, o.subid) NOT IN (SELECT subid FROM cmp24.subtree)
AND (o.subid IS NULL OR n.subid IS NULL
  OR abs(o.q_local - n.q_local) > 1e-9 OR abs(o.q_acc - n.q_acc) > 1e-9)
GROUP BY 1 ORDER BY 1 LIMIT 20;
SQL
echo "== done $(date -u +%H:%M:%SZ)"
