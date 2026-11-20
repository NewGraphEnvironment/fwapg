-- fwapg#4 Phase 1: the prototype's zero-area segments, split by whether their
-- own stream has a polygon lower down (the polygon they lie in is coded at a
-- lower local code) or no polygon at all.
\pset format unaligned
\pset tuples_only on
SET work_mem = '1GB';
WITH zero AS (
  SELECT s.*, a.downstream_id
  FROM fwapg.proto4_area a
  INNER JOIN fwapg.proto4_seg s USING (linear_feature_id)
  WHERE a.upstream_area_ha = 0
),
own AS (SELECT DISTINCT wscode_ltree FROM fwapg.proto4_poly WHERE linear_feature_id IS NOT NULL AND levels_up = 0)
SELECT 'zero', z.source, o.wscode_ltree IS NOT NULL AS stream_has_a_polygon_lower_down,
  count(*) AS segments, count(DISTINCT z.wscode_ltree) AS streams, round(sum(z.length_metre)::numeric / 1000) AS km,
  count(*) FILTER (WHERE z.downstream_id IS NULL) AS outlets,
  round((percentile_cont(0.5) WITHIN GROUP (ORDER BY z.length_metre))::numeric) AS median_segment_m
FROM zero z
LEFT JOIN own o ON o.wscode_ltree = z.wscode_ltree
GROUP BY 2, 3 ORDER BY 4 DESC;

-- streams with no polygon at all: how long is the whole stream, and what is the
-- polygon their mouth lies in assigned to
WITH zero AS (
  SELECT s.wscode_ltree, s.blue_line_key, sum(s.length_metre) AS len_m, count(*) AS n
  FROM fwapg.proto4_area a
  INNER JOIN fwapg.proto4_seg s USING (linear_feature_id)
  WHERE a.upstream_area_ha = 0
  AND NOT EXISTS (SELECT 1 FROM fwapg.proto4_poly p WHERE p.wscode_ltree = s.wscode_ltree AND p.linear_feature_id IS NOT NULL AND p.levels_up = 0)
  GROUP BY 1, 2
)
SELECT 'no-polygon lines by length', width_bucket(len_m, ARRAY[100, 500, 1000, 5000, 20000]) AS bucket_100_500_1k_5k_20k,
  count(*) AS lines, round(sum(len_m)::numeric / 1000) AS km
FROM zero GROUP BY 2 ORDER BY 2;

-- outlets of the tree under the Fraser's code, by QA kind, with their area
SELECT 'fraser outlets', coalesce(q.kind, 'edge of BC'), count(*), round(sum(a.upstream_area_ha)::numeric) AS ha
FROM fwapg.proto4_area a
INNER JOIN fwapg.proto4_seg s USING (linear_feature_id)
LEFT JOIN (SELECT DISTINCT ON (linear_feature_id) linear_feature_id, kind FROM fwapg.mainflow_tree_qa ORDER BY linear_feature_id, kind) q USING (linear_feature_id)
WHERE a.downstream_id IS NULL AND s.wscode_ltree <@ '100'
GROUP BY 2 ORDER BY 4 DESC;

-- all outlets by kind, province-wide
SELECT 'outlets', coalesce(q.kind, 'edge of BC'), count(*), round(sum(a.upstream_area_ha)::numeric) AS ha,
  round(max(a.upstream_area_ha)::numeric) AS largest_ha
FROM fwapg.proto4_area a
LEFT JOIN (SELECT DISTINCT ON (linear_feature_id) linear_feature_id, kind FROM fwapg.mainflow_tree_qa ORDER BY linear_feature_id, kind) q USING (linear_feature_id)
WHERE a.downstream_id IS NULL
GROUP BY 2 ORDER BY 4 DESC;
