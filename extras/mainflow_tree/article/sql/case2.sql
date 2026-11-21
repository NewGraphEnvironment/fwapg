-- Case 2: a polygon moved up its line through reaches with no polygon of their
-- own. Moved: method pair, a local code under its own watershed code, and given
-- to a segment of another local code (15,848 polygons; with the 19 bad-code
-- polygons rule 1 also moves, the README's 15,867). Chosen: LSKE or KLUM, 50 to
-- 500 ha, the most segments crossed on its line between its own local code and
-- the segment it landed on, then the lowest watershed_feature_id: 7745172.
pick AS (
  SELECT p.watershed_feature_id, w.geom
  FROM fwapg.mainflow_tree_area_polygons p
  INNER JOIN whse_basemapping.fwa_watersheds_poly w ON w.watershed_feature_id = p.watershed_feature_id
  INNER JOIN whse_basemapping.fwa_stream_networks_sp s ON s.linear_feature_id = p.linear_feature_id
  WHERE p.method = 'pair' AND w.localcode_ltree <@ w.wscode_ltree AND s.localcode_ltree <> w.localcode_ltree
    AND w.watershed_group_code IN ('LSKE', 'KLUM') AND p.area_ha BETWEEN 50 AND 500
  ORDER BY (SELECT count(*) FROM whse_basemapping.fwa_stream_networks_sp x
            WHERE x.blue_line_key = s.blue_line_key AND x.localcode_ltree > w.localcode_ltree
              AND x.downstream_route_measure < s.downstream_route_measure) DESC,
           p.watershed_feature_id
  LIMIT 1
),
view AS (SELECT ST_Buffer(ST_Envelope(geom), 500) AS geom FROM pick),
seg_set AS (
  SELECT s.linear_feature_id,
    s.linear_feature_id = (SELECT linear_feature_id FROM fwapg.mainflow_tree_area_polygons p JOIN pick USING (watershed_feature_id)) AS focus
  FROM whse_basemapping.fwa_stream_networks_sp s CROSS JOIN view v
  WHERE s.geom && v.geom AND ST_Intersects(s.geom, v.geom)
),
poly_set AS (
  SELECT w.watershed_feature_id, w.watershed_feature_id IN (SELECT watershed_feature_id FROM pick) AS focus,
    NULL::text AS kind,
    CASE WHEN w.watershed_feature_id IN (SELECT watershed_feature_id FROM pick) THEN true END AS moved
  FROM whse_basemapping.fwa_watersheds_poly w CROSS JOIN view v
  WHERE w.geom && v.geom AND ST_Intersects(w.geom, v.geom)
)
