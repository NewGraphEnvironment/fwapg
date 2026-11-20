-- The search behind case3.sql's three polygons (about 70 s on the provincial
-- database). Run by hand; the extract reads the ids fixed in case3.sql.
WITH sc AS (
  SELECT s.linear_feature_id, s.wscode_ltree, s.localcode_ltree, s.geom,
    ST_LineInterpolatePoint(ST_Force2D(ST_LineMerge(s.geom)), 0.5) AS mid
  FROM whse_basemapping.fwa_stream_networks_sp s
  INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t ON t.linear_feature_id = s.linear_feature_id
  WHERE t.source IN ('reattached', 'followed') AND s.watershed_group_code IN ('MORR', 'NECR', 'BULK', 'KISP', 'KOTL')
),
w AS (
  SELECT w.*, p.method
  FROM whse_basemapping.fwa_watersheds_poly w
  INNER JOIN fwapg.mainflow_tree_area_polygons p ON p.watershed_feature_id = w.watershed_feature_id
  WHERE w.watershed_group_code IN ('MORR', 'NECR', 'BULK', 'KISP', 'KOTL')
),
rt AS (SELECT watershed_feature_id, watershed_group_code AS g, geom FROM w WHERE method = 'pair_side'),
tc AS (
  SELECT watershed_feature_id, watershed_group_code AS g, geom FROM w
  WHERE method <> 'pair_side'
    AND EXISTS (SELECT 1 FROM sc WHERE sc.geom && w.geom AND ST_Intersects(sc.geom, w.geom))
    AND NOT EXISTS (SELECT 1 FROM sc WHERE sc.mid && w.geom AND ST_Contains(w.geom, sc.mid))
),
nt AS (
  SELECT watershed_feature_id, watershed_group_code AS g, geom FROM w
  WHERE method <> 'pair_side'
    AND EXISTS (SELECT 1 FROM sc WHERE sc.wscode_ltree = w.wscode_ltree AND sc.localcode_ltree = w.localcode_ltree)
    AND NOT EXISTS (
      SELECT 1 FROM whse_basemapping.fwa_stream_networks_sp m
      INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree mt ON mt.linear_feature_id = m.linear_feature_id
      WHERE mt.source = 'mainflow' AND m.wscode_ltree = w.wscode_ltree AND m.localcode_ltree = w.localcode_ltree)
    AND NOT EXISTS (SELECT 1 FROM sc WHERE sc.geom && w.geom AND ST_Intersects(sc.geom, w.geom))
)
SELECT rt.g, rt.watershed_feature_id AS runs_through, tc.watershed_feature_id AS touches, nt.watershed_feature_id AS not_touching,
  round(greatest(ST_Distance(rt.geom, tc.geom), ST_Distance(rt.geom, nt.geom), ST_Distance(tc.geom, nt.geom))) AS spread_m
FROM rt
INNER JOIN tc ON tc.g = rt.g AND ST_DWithin(rt.geom, tc.geom, 3000)
INNER JOIN nt ON nt.g = rt.g AND ST_DWithin(rt.geom, nt.geom, 3000) AND ST_DWithin(tc.geom, nt.geom, 3000)
ORDER BY array_position(ARRAY['MORR', 'NECR', 'BULK', 'KISP', 'KOTL'], rt.g), spread_m,
  rt.watershed_feature_id, tc.watershed_feature_id, nt.watershed_feature_id
LIMIT 1;
