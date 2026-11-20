-- Case 6: a dead end carried across a gap and one where the network ends. The
-- closest such pair in one watershed group (kind dead_end in
-- fwapg.mainflow_tree_qa; downstream_method junction against NULL), then ids:
-- TUTR 212039207 (junction) and 212039334 (an outlet), 77 m apart. The segment
-- the first is carried to is kept, wherever it lies.
picked (linear_feature_id) AS (VALUES (212039207::bigint), (212039334::bigint)),
view AS (
  SELECT ST_Buffer(ST_Envelope(ST_Collect(s.geom)), 600) AS geom
  FROM whse_basemapping.fwa_stream_networks_sp s
  WHERE s.linear_feature_id IN (SELECT linear_feature_id FROM picked)
     OR s.linear_feature_id IN (SELECT a.downstream_id FROM fwapg.mainflow_tree_area a INNER JOIN picked USING (linear_feature_id))
),
seg_set AS (
  SELECT s.linear_feature_id, s.linear_feature_id IN (SELECT linear_feature_id FROM picked) AS focus
  FROM whse_basemapping.fwa_stream_networks_sp s CROSS JOIN view v
  WHERE s.geom && v.geom AND ST_Intersects(s.geom, v.geom)
),
poly_set AS (
  SELECT w.watershed_feature_id, false AS focus, NULL::text AS kind, NULL::boolean AS moved
  FROM whse_basemapping.fwa_watersheds_poly w CROSS JOIN view v
  WHERE w.geom && v.geom AND ST_Intersects(w.geom, v.geom)
)
