-- Pointer walk (#34) over fwapg.downstream_ids, included with psql variables
-- walk (full or 1km), grp, lo, hi, out. The INSERT must stay the last statement.
--
-- ord is the position on the chain from the origin's segment (1). cum_m is the
-- distance from the origin to each segment's downstream end: the origin's
-- partial segment, then step_m per step (01_downstream_ids.sql). The 1 km walk
-- takes the next segment while the current one ends within 1,000 m, so every
-- segment that starts within 1,000 m of the origin is returned.

-- :explain prefixes the INSERT with EXPLAIN (05_explain.sql); empty otherwise
\if :{?explain}
\else
\set explain ''
\endif

:explain INSERT INTO :out (origin_id, linear_feature_id, ord, cum_m)
WITH RECURSIVE walk AS (
  SELECT o.origin_id, o.linear_feature_id, 1 AS ord, o.measure - o.seg_drm AS cum_m
  FROM fwapg.bench_origins o
  WHERE o.grp = :'grp' AND o.rnk BETWEEN :lo AND :hi
  UNION ALL
  SELECT w.origin_id, d.downstream_id, w.ord + 1, w.cum_m + d.step_m
  FROM walk w
  INNER JOIN fwapg.downstream_ids d ON d.linear_feature_id = w.linear_feature_id
  WHERE d.downstream_id IS NOT NULL
  AND (:'walk' = 'full' OR w.cum_m < 1000)
)
SELECT origin_id, linear_feature_id, ord, cum_m
FROM walk;
