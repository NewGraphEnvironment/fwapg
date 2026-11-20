-- fwapg#4 Phase 1: tree segments by what the lookup gives them, and polygons by
-- how a tree segment could claim them.
\pset format unaligned
\pset tuples_only on
SET work_mem = '1GB';

-- A. tree segments by lookup class and source (issue: 8,111 another stream's, 2,941 no row)
SELECT 'A', t.source,
  CASE WHEN l.linear_feature_id IS NULL THEN 'no lookup row'
       WHEN w.wscode_ltree = s.wscode_ltree AND w.localcode_ltree = s.localcode_ltree THEN 'own codes'
       WHEN w.wscode_ltree = s.wscode_ltree THEN 'own watershed code, another local code'
       ELSE 'another stream''s polygon' END AS class,
  count(*), count(*) FILTER (WHERE s.edge_type = 1450) AS connectors_1450,
  count(*) FILTER (WHERE s.localcode_ltree IS NULL) AS null_localcode
FROM whse_basemapping.fwa_stream_networks_mainflow_tree t
INNER JOIN whse_basemapping.fwa_stream_networks_sp s USING (linear_feature_id)
LEFT JOIN whse_basemapping.fwa_streams_watersheds_lut l USING (linear_feature_id)
LEFT JOIN whse_basemapping.fwa_watersheds_poly w ON w.watershed_feature_id = l.watershed_feature_id
GROUP BY 2, 3 ORDER BY 2, 4 DESC;

-- B. tree segments with no lookup row, by edge type and whether they have a local code
SELECT 'B', s.edge_type, s.localcode_ltree IS NULL AS null_localcode, s.edge_type = 6010 OR s.local_watershed_code IS NULL AS excluded_by_lut, count(*)
FROM whse_basemapping.fwa_stream_networks_mainflow_tree t
INNER JOIN whse_basemapping.fwa_stream_networks_sp s USING (linear_feature_id)
LEFT JOIN whse_basemapping.fwa_streams_watersheds_lut l USING (linear_feature_id)
WHERE l.linear_feature_id IS NULL
GROUP BY 2, 3, 4 ORDER BY 5 DESC;

-- C. polygons whose watershed code is not on any tree segment: is the code on
-- the network at all, and what kind of polygon is it
WITH tree_ws AS (
  SELECT DISTINCT s.wscode_ltree FROM whse_basemapping.fwa_stream_networks_sp s
  INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t USING (linear_feature_id)
),
net_ws AS (SELECT DISTINCT wscode_ltree FROM whse_basemapping.fwa_stream_networks_sp)
SELECT 'C',
  n.wscode_ltree IS NOT NULL AS code_on_network,
  CASE WHEN w.waterbody_key IS NULL OR w.waterbody_key = 0 THEN 'land' ELSE coalesce(wb.waterbody_type, 'waterbody, type unknown') END AS kind,
  nlevel(w.wscode_ltree) = 1 AS top_level_code,
  count(*), round(sum(w.area_ha)::numeric) AS ha
FROM whse_basemapping.fwa_watersheds_poly w
LEFT JOIN tree_ws tw ON tw.wscode_ltree = w.wscode_ltree
LEFT JOIN net_ws n ON n.wscode_ltree = w.wscode_ltree
LEFT JOIN (SELECT DISTINCT ON (waterbody_key) waterbody_key, waterbody_type FROM whse_basemapping.fwa_waterbodies) wb ON wb.waterbody_key = w.waterbody_key
WHERE tw.wscode_ltree IS NULL AND NOT w.wscode_ltree <@ '999'
GROUP BY 2, 3, 4 ORDER BY 5 DESC;

-- D. polygons whose watershed code is in the tree and whose local code is on no
-- tree segment: is the local code on a dropped network segment, and is there a
-- tree segment on the code at a lower local code
WITH tree_codes AS (
  SELECT DISTINCT s.wscode_ltree, s.localcode_ltree FROM whse_basemapping.fwa_stream_networks_sp s
  INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t USING (linear_feature_id)
),
net_codes AS (SELECT DISTINCT wscode_ltree, localcode_ltree FROM whse_basemapping.fwa_stream_networks_sp)
SELECT 'D',
  n.wscode_ltree IS NOT NULL AS codes_on_dropped_segment,
  EXISTS (SELECT 1 FROM tree_codes c WHERE c.wscode_ltree = w.wscode_ltree AND c.localcode_ltree < w.localcode_ltree) AS tree_segment_at_lower_local_code,
  w.localcode_ltree IS NULL AS poly_null_localcode,
  count(*), round(sum(w.area_ha)::numeric) AS ha
FROM whse_basemapping.fwa_watersheds_poly w
INNER JOIN (SELECT DISTINCT wscode_ltree FROM tree_codes) tw ON tw.wscode_ltree = w.wscode_ltree
LEFT JOIN tree_codes c ON c.wscode_ltree = w.wscode_ltree AND c.localcode_ltree = w.localcode_ltree
LEFT JOIN net_codes n ON n.wscode_ltree = w.wscode_ltree AND n.localcode_ltree = w.localcode_ltree
WHERE c.wscode_ltree IS NULL
GROUP BY 2, 3, 4 ORDER BY 5 DESC;
