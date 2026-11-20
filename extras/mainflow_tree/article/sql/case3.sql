-- Case 3: land beside a river and its side channels, three kinds, in MORR, the
-- first of the groups with mapped floodplain (MORR, NECR, BULK, KISP, KOTL) to
-- hold all three within 3 km of each other, then the least spread, then ids:
--   runs_through 7662562: pair_side, a side-channel segment's midpoint inside;
--   touches 7662598: given to main flow, a side-channel segment intersects it,
--     no side-channel midpoint inside;
--   not_touching 9742603: codes on side-channel segments only, given to main
--     flow, no side-channel segment intersects it.
-- The search is case3_search.sql; the three ids are fixed here so the
-- extract does not re-run a 70 s search.
picked (watershed_feature_id, kind) AS (
  VALUES (7662562, 'runs_through'), (7662598, 'touches'), (9742603, 'not_touching')
),
view AS (
  SELECT ST_Buffer(ST_Envelope(ST_Collect(w.geom)), 400) AS geom
  FROM whse_basemapping.fwa_watersheds_poly w INNER JOIN picked USING (watershed_feature_id)
),
seg_set AS (
  SELECT s.linear_feature_id, false AS focus
  FROM whse_basemapping.fwa_stream_networks_sp s CROSS JOIN view v
  WHERE s.geom && v.geom AND ST_Intersects(s.geom, v.geom)
),
poly_set AS (
  SELECT w.watershed_feature_id, k.kind IS NOT NULL AS focus, k.kind, NULL::boolean AS moved
  FROM whse_basemapping.fwa_watersheds_poly w CROSS JOIN view v
  LEFT JOIN picked k ON k.watershed_feature_id = w.watershed_feature_id
  WHERE w.geom && v.geom AND ST_Intersects(w.geom, v.geom)
)
