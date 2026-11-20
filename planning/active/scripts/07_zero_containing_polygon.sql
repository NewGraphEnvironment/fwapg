-- fwapg#4 Phase 1: the polygon each no-polygon zero segment lies in (by its
-- midpoint), and whether the codes gave that polygon to a tree segment.
\pset format unaligned
\pset tuples_only on
WITH zero AS (
  SELECT s.linear_feature_id, s.wscode_ltree, s.length_metre, a.downstream_id
  FROM fwapg.proto4_area a
  INNER JOIN fwapg.proto4_seg s USING (linear_feature_id)
  WHERE a.upstream_area_ha = 0
  AND NOT EXISTS (SELECT 1 FROM fwapg.proto4_poly p WHERE p.wscode_ltree = s.wscode_ltree AND p.linear_feature_id IS NOT NULL AND p.levels_up = 0)
),
hit AS (
  SELECT z.linear_feature_id, z.length_metre, z.downstream_id, count(w.watershed_feature_id) AS n_polys,
    min(w.watershed_feature_id) AS watershed_feature_id
  FROM zero z
  INNER JOIN whse_basemapping.fwa_stream_networks_sp s USING (linear_feature_id)
  LEFT JOIN whse_basemapping.fwa_watersheds_poly w ON ST_Intersects(ST_LineInterpolatePoint(s.geom, 0.5), w.geom)
  GROUP BY 1, 2, 3
)
SELECT 'containing polygon',
  CASE WHEN h.n_polys = 0 THEN 'in no polygon'
       WHEN p.linear_feature_id IS NULL AND p.wscode_ltree <@ '999' THEN 'polygon under 999'
       WHEN p.linear_feature_id IS NULL THEN 'polygon the codes give to no segment'
       WHEN p.same_pair THEN 'polygon given by its code pair'
       WHEN p.levels_up = 0 THEN 'polygon given at a lower local code'
       ELSE 'polygon given through an ancestor code' END AS class,
  count(*) AS segments, round(sum(h.length_metre)::numeric / 1000) AS km,
  count(*) FILTER (WHERE h.downstream_id IS NULL) AS outlets,
  count(DISTINCT h.watershed_feature_id) AS polygons,
  round(avg(p.area_ha)::numeric) AS mean_polygon_ha, max(h.n_polys) AS max_polys_at_midpoint
FROM hit h
LEFT JOIN fwapg.proto4_poly p USING (watershed_feature_id)
GROUP BY 2 ORDER BY 3 DESC;
