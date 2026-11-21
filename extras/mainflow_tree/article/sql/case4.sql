-- Case 4: the Beaver River cross-border polygon 1000002557 (BEAV), 766,913 ha,
-- given by rule 4 (lower) to 868144442 on blue line 359572098, the main line
-- overrides.csv keeps; 359024601 is the other main line of the same code.
-- The view is the polygon; streams are the two Beaver lines' segments and the
-- network within 2 km of the segment it was given to.
view AS (
  SELECT geom FROM whse_basemapping.fwa_watersheds_poly WHERE watershed_feature_id = 1000002557
),
near AS (
  SELECT ST_Buffer(geom, 2000) AS geom FROM whse_basemapping.fwa_stream_networks_sp WHERE linear_feature_id = 868144442
),
seg_set AS (
  SELECT s.linear_feature_id, s.linear_feature_id = 868144442 AS focus
  FROM whse_basemapping.fwa_stream_networks_sp s CROSS JOIN view v
  WHERE s.blue_line_key IN (359572098, 359024601) AND s.geom && v.geom AND ST_Intersects(s.geom, ST_Buffer(v.geom, 2000))
  UNION
  SELECT s.linear_feature_id, s.linear_feature_id = 868144442
  FROM whse_basemapping.fwa_stream_networks_sp s CROSS JOIN near n
  WHERE s.geom && n.geom AND ST_Intersects(s.geom, n.geom)
),
poly_set AS (
  SELECT w.watershed_feature_id, w.watershed_feature_id = 1000002557 AS focus, NULL::text AS kind, NULL::boolean AS moved
  FROM whse_basemapping.fwa_watersheds_poly w CROSS JOIN near n
  WHERE w.watershed_feature_id = 1000002557 OR (w.geom && n.geom AND ST_Intersects(w.geom, n.geom))
)
