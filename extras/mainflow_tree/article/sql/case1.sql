-- Case 1: Skeena test side channel 360216952 (LSKE) and tributary 360884603,
-- which enters it, down through side channel 360216962 to main flow at
-- 123043992, where its water meets the Skeena's. Ids from the README's
-- "test side channels" and from walking downstream_id (2026-11-20 build).
view AS (
  SELECT ST_Buffer(ST_Envelope(ST_Collect(s.geom)), 300) AS geom
  FROM whse_basemapping.fwa_stream_networks_sp s
  INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t ON t.linear_feature_id = s.linear_feature_id
  WHERE s.blue_line_key IN (360216952, 360216962)
     OR s.linear_feature_id IN (123039760, 123043992)
),
seg_set AS (
  SELECT s.linear_feature_id,
    s.blue_line_key IN (360216952, 360216962) AND t.linear_feature_id IS NOT NULL AS focus
  FROM whse_basemapping.fwa_stream_networks_sp s
  CROSS JOIN view v
  LEFT JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t ON t.linear_feature_id = s.linear_feature_id
  WHERE s.geom && v.geom AND ST_Intersects(s.geom, v.geom)
),
poly_set AS (
  SELECT w.watershed_feature_id, false AS focus, NULL::text AS kind, NULL::boolean AS moved
  FROM whse_basemapping.fwa_watersheds_poly w CROSS JOIN view v
  WHERE w.geom && v.geom AND ST_Intersects(w.geom, v.geom)
)
