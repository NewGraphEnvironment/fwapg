-- Case 7: the one main-flow segment that differs from the lookup with nothing
-- routed differently and no anomaly in its codes (class IS NULL in
-- fwapg.mainflow_tree_area_qa): 212038783 (TUTR).
pick AS (
  SELECT linear_feature_id FROM fwapg.mainflow_tree_area_qa WHERE class IS NULL AND source = 'mainflow'
),
view AS (
  SELECT ST_Buffer(ST_Envelope(s.geom), 800) AS geom
  FROM whse_basemapping.fwa_stream_networks_sp s INNER JOIN pick USING (linear_feature_id)
),
seg_set AS (
  SELECT s.linear_feature_id, s.linear_feature_id IN (SELECT linear_feature_id FROM pick) AS focus
  FROM whse_basemapping.fwa_stream_networks_sp s CROSS JOIN view v
  WHERE s.geom && v.geom AND ST_Intersects(s.geom, v.geom)
),
poly_set AS (
  SELECT w.watershed_feature_id,
    w.watershed_feature_id IN (SELECT l.watershed_feature_id FROM whse_basemapping.fwa_streams_watersheds_lut l INNER JOIN pick USING (linear_feature_id)) AS focus,
    NULL::text AS kind, NULL::boolean AS moved
  FROM whse_basemapping.fwa_watersheds_poly w CROSS JOIN view v
  WHERE w.geom && v.geom AND ST_Intersects(w.geom, v.geom)
)
