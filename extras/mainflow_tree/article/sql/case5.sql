-- Case 5: a stream with no polygon of its own. The share segment whose share is
-- nearest the median share (13.69 ha), then the lowest linear_feature_id:
-- 180011290 (SHEK), from polygon 8442664, which gives shares to 8 segments.
-- All 8 are kept, and the segment the polygon was given to.
pick AS (
  SELECT s.linear_feature_id, s.watershed_feature_id
  FROM fwapg.mainflow_tree_area_shares s
  CROSS JOIN (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY share_ha) AS med FROM fwapg.mainflow_tree_area_shares) m
  ORDER BY abs(s.share_ha - m.med), s.linear_feature_id
  LIMIT 1
),
view AS (
  SELECT ST_Buffer(ST_Envelope(w.geom), 300) AS geom
  FROM whse_basemapping.fwa_watersheds_poly w INNER JOIN pick USING (watershed_feature_id)
),
seg_set AS (
  SELECT s.linear_feature_id, s.linear_feature_id = (SELECT linear_feature_id FROM pick) AS focus
  FROM whse_basemapping.fwa_stream_networks_sp s CROSS JOIN view v
  WHERE s.geom && v.geom AND ST_Intersects(s.geom, v.geom)
  UNION
  SELECT x.linear_feature_id, x.linear_feature_id = (SELECT linear_feature_id FROM pick)
  FROM fwapg.mainflow_tree_area_shares x WHERE x.watershed_feature_id = (SELECT watershed_feature_id FROM pick)
  UNION
  SELECT p.linear_feature_id, false
  FROM fwapg.mainflow_tree_area_polygons p WHERE p.watershed_feature_id = (SELECT watershed_feature_id FROM pick)
),
poly_set AS (
  SELECT w.watershed_feature_id, w.watershed_feature_id = (SELECT watershed_feature_id FROM pick) AS focus,
    NULL::text AS kind, NULL::boolean AS moved
  FROM whse_basemapping.fwa_watersheds_poly w CROSS JOIN view v
  WHERE w.geom && v.geom AND ST_Intersects(w.geom, v.geom)
)
