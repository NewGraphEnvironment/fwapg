-- fwapg#4 Phase 1: which CTE of FWA_WatershedAtMeasure()'s non-lake branch is
-- empty where the function returns no row. The CTEs are the function's own
-- (db/migrations/202610131654__watershedatmeasure_drop_exbc.sql), counted.
-- psql -v blk=360216952 -v m=1800 -f 02_watershedatmeasure_trace.sql
WITH ref_point_a AS (
  SELECT s.linear_feature_id, s.blue_line_key, s.downstream_route_measure AS measure_str,
    :m::float AS measure_pt, s.wscode_ltree, s.localcode_ltree, s.waterbody_key, s.edge_type,
    CASE WHEN r.feature_code = 'GA03950000' THEN 'C' ELSE wb.waterbody_type END AS waterbody_type,
    (ST_Dump(ST_LocateAlong(s.geom, :m::float))).geom AS geom_pt
  FROM whse_basemapping.fwa_stream_networks_sp s
  LEFT OUTER JOIN whse_basemapping.fwa_waterbodies wb ON s.waterbody_key = wb.waterbody_key
  LEFT OUTER JOIN whse_basemapping.fwa_manmade_waterbodies_poly r ON s.waterbody_key = r.waterbody_key
  WHERE s.blue_line_key = :blk AND s.downstream_route_measure <= :m::float
  ORDER BY s.downstream_route_measure DESC LIMIT 1
),
ref_point AS (
  SELECT r.*, p.waterbody_key AS waterbody_key_poly, p.watershed_feature_id AS poly_id,
    p.wscode_ltree AS poly_wscode, p.localcode_ltree AS poly_localcode
  FROM ref_point_a r
  INNER JOIN whse_basemapping.fwa_watersheds_poly p ON ST_Intersects(r.geom_pt, p.geom)
  LIMIT 1
),
wsd AS (
  SELECT array_agg(watershed_feature_id) AS wsds, ST_Union(wsd.geom) AS geom
  FROM whse_basemapping.fwa_watersheds_poly wsd
  INNER JOIN ref_point pt ON ST_DWithin(wsd.geom, pt.geom_pt, 5)
),
covered AS (
  SELECT str.linear_feature_id
  FROM whse_basemapping.fwa_stream_networks_sp str
  INNER JOIN ref_point refpt ON str.blue_line_key = refpt.blue_line_key AND str.wscode_ltree = refpt.wscode_ltree
  INNER JOIN wsd ON ST_CoveredBy(
    ST_LineSubstring(str.geom, .004 / ST_Length(str.geom), (ST_Length(str.geom) - .004) / ST_Length(str.geom)),
    wsd.geom)
)
SELECT
  (SELECT count(*) FROM ref_point_a) AS ref_point_a,
  (SELECT count(*) FROM ref_point) AS ref_point,
  r.linear_feature_id, r.edge_type, r.wscode_ltree, r.localcode_ltree, r.waterbody_key, r.waterbody_type,
  r.waterbody_key_poly, r.poly_id, r.poly_wscode, r.poly_localcode,
  (SELECT cardinality(wsds) FROM wsd) AS polys_within_5m,
  (SELECT count(*) FROM covered) AS segments_covered,
  (SELECT count(*) FROM whse_basemapping.fwa_stream_networks_sp s2
   WHERE s2.blue_line_key = r.blue_line_key AND s2.wscode_ltree = r.wscode_ltree) AS segments_same_line_and_code
FROM ref_point_a r0
LEFT JOIN ref_point r ON true;
