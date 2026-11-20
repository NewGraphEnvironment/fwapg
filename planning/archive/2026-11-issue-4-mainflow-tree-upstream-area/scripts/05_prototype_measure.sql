-- fwapg#4 Phase 1: what the prototype (04_prototype.sql) leaves, by class.
\pset format unaligned
\pset tuples_only on
SET work_mem = '1GB';

-- a. pointers by method, and what the segments with none are in the topology QA
SELECT 'a pointer', coalesce(d.method, 'none'), coalesce(q.kind, '-') AS qa_kind, count(*), min(d.path_step), max(d.path_step)
FROM fwapg.proto4_down d
LEFT JOIN (SELECT DISTINCT ON (linear_feature_id) linear_feature_id, kind FROM fwapg.mainflow_tree_qa ORDER BY linear_feature_id, kind) q USING (linear_feature_id)
GROUP BY 2, 3 ORDER BY 2, 3;

-- b. polygons by how they were assigned
SELECT 'b polygon',
  CASE WHEN p.wscode_ltree IS NULL THEN 'no code'
       WHEN p.wscode_ltree <@ '999' THEN 'under 999'
       WHEN p.linear_feature_id IS NULL AND nlevel(p.wscode_ltree) = 1 THEN 'unassigned, one-label code'
       WHEN p.linear_feature_id IS NULL THEN 'unassigned, no ancestor in the tree'
       WHEN p.same_pair THEN 'same code pair, ' || p.source
       WHEN p.levels_up = 0 THEN 'own stream, a lower local code, ' || p.source
       ELSE 'ancestor code, ' || least(p.levels_up, 3) || '+ levels up' END AS class,
  count(*), round(sum(p.area_ha)::numeric) AS ha
FROM fwapg.proto4_poly p
GROUP BY 2 ORDER BY 3 DESC;

-- c. segments with zero area: by source, and their subtrees (a root is a zero
-- segment whose downstream segment has area, or which is an outlet)
SELECT 'c zero', s.source, count(*) AS segments, count(DISTINCT s.blue_line_key) AS lines,
  round(sum(s.length_metre)::numeric / 1000) AS km,
  count(*) FILTER (WHERE a.downstream_id IS NULL) AS zero_outlets,
  count(*) FILTER (WHERE dn.upstream_area_ha > 0) AS subtree_roots
FROM fwapg.proto4_area a
INNER JOIN fwapg.proto4_seg s USING (linear_feature_id)
LEFT JOIN fwapg.proto4_area dn ON dn.linear_feature_id = a.downstream_id
WHERE a.upstream_area_ha = 0
GROUP BY 2 ORDER BY 3 DESC;

-- c2. zero segments by what the lookup gives them
SELECT 'c2 zero by lookup',
  CASE WHEN l.linear_feature_id IS NULL THEN 'no lookup row'
       WHEN w.wscode_ltree = s.wscode_ltree AND w.localcode_ltree = s.localcode_ltree THEN 'own codes'
       WHEN w.wscode_ltree = s.wscode_ltree THEN 'own watershed code, another local code'
       ELSE 'another stream''s polygon' END AS class,
  count(*), round(avg(w.area_ha)::numeric, 1) AS mean_polygon_ha
FROM fwapg.proto4_area a
INNER JOIN fwapg.proto4_seg s USING (linear_feature_id)
LEFT JOIN whse_basemapping.fwa_streams_watersheds_lut l USING (linear_feature_id)
LEFT JOIN whse_basemapping.fwa_watersheds_poly w ON w.watershed_feature_id = l.watershed_feature_id
WHERE a.upstream_area_ha = 0
GROUP BY 2 ORDER BY 3 DESC;

-- d. the four test side channels and the tributary mouth
SELECT 'd side channel', s.blue_line_key, s.linear_feature_id, round(s.drm::numeric, 1), s.source,
  round(a.local_area_ha::numeric, 1) AS local_ha, round(a.upstream_area_ha::numeric, 1) AS area_ha
FROM fwapg.proto4_area a
INNER JOIN fwapg.proto4_seg s USING (linear_feature_id)
WHERE s.blue_line_key IN (360222215, 360237491, 360222216, 360216952) OR s.linear_feature_id IN (87078680, 245024871)
ORDER BY 2, 4;

-- e. basins: area at the mouth, the assigned polygons under the code, the lookup at the mouth
SELECT 'e basin', b.name,
  round(a.upstream_area_ha::numeric, 1) AS tree_ha,
  (SELECT round(sum(p.area_ha)::numeric, 1) FROM fwapg.proto4_poly p WHERE p.wscode_ltree <@ b.code AND p.linear_feature_id IS NOT NULL) AS assigned_polygons_ha,
  (SELECT round(sum(ST_Area(w.geom) / 10000)::numeric, 1) FROM whse_basemapping.fwa_watersheds_poly w WHERE w.wscode_ltree <@ b.code) AS all_polygons_ha,
  round(ua.upstream_area_ha::numeric, 1) AS lookup_ha
FROM (VALUES ('Skeena', '400'::ltree), ('Nechako', '100.567134'::ltree), ('Fraser', '100'::ltree)) AS b (name, code)
INNER JOIN LATERAL (
  SELECT s.linear_feature_id FROM fwapg.proto4_seg s
  WHERE s.wscode_ltree = b.code AND s.source = 'mainflow' ORDER BY s.drm LIMIT 1
) m ON true
INNER JOIN fwapg.proto4_area a ON a.linear_feature_id = m.linear_feature_id
LEFT JOIN whse_basemapping.fwa_streams_watersheds_lut l ON l.linear_feature_id = m.linear_feature_id
LEFT JOIN whse_basemapping.fwa_watersheds_upstream_area ua ON ua.watershed_feature_id = l.watershed_feature_id;

-- f. against the lookup, on segments whose lookup polygon has both their codes
SELECT 'f lookup', s.source,
  CASE WHEN abs(a.upstream_area_ha - ua.upstream_area_ha) <= 1e-6 * greatest(ua.upstream_area_ha, 1) THEN 'equal'
       WHEN a.upstream_area_ha < ua.upstream_area_ha THEN 'tree lower'
       ELSE 'tree higher' END AS cmp,
  count(*)
FROM fwapg.proto4_area a
INNER JOIN fwapg.proto4_seg s USING (linear_feature_id)
INNER JOIN whse_basemapping.fwa_streams_watersheds_lut l USING (linear_feature_id)
INNER JOIN whse_basemapping.fwa_watersheds_poly w ON w.watershed_feature_id = l.watershed_feature_id
INNER JOIN whse_basemapping.fwa_watersheds_upstream_area ua ON ua.watershed_feature_id = l.watershed_feature_id
WHERE w.wscode_ltree = s.wscode_ltree AND w.localcode_ltree = s.localcode_ltree
GROUP BY 2, 3 ORDER BY 2, 4 DESC;

-- g. main-flow code pairs that appear in more than one run on their line, and
-- the area of the polygons on those pairs
WITH runs AS (
  SELECT wscode_ltree, localcode_ltree, blue_line_key,
    (localcode_ltree IS DISTINCT FROM lag(localcode_ltree) OVER (PARTITION BY blue_line_key ORDER BY drm))::int AS starts
  FROM fwapg.proto4_seg
  WHERE source = 'mainflow'
),
multi AS (
  SELECT wscode_ltree, localcode_ltree
  FROM runs WHERE localcode_ltree IS NOT NULL
  GROUP BY wscode_ltree, localcode_ltree
  HAVING sum(starts) > 1 OR count(DISTINCT blue_line_key) > 1
)
SELECT 'g pairs in more than one run', count(*),
  (SELECT count(*) FROM fwapg.proto4_poly p INNER JOIN multi m ON m.wscode_ltree = p.wscode_ltree AND m.localcode_ltree = p.localcode_ltree) AS polygons,
  (SELECT round(sum(p.area_ha)::numeric) FROM fwapg.proto4_poly p INNER JOIN multi m ON m.wscode_ltree = p.wscode_ltree AND m.localcode_ltree = p.localcode_ltree) AS ha
FROM multi;

-- h. conservation: the outlets' areas against the assigned polygons
SELECT 'h conservation',
  (SELECT round(sum(upstream_area_ha)::numeric, 1) FROM fwapg.proto4_area WHERE downstream_id IS NULL) AS outlets_ha,
  (SELECT round(sum(area_ha)::numeric, 1) FROM fwapg.proto4_poly WHERE linear_feature_id IS NOT NULL) AS assigned_ha,
  (SELECT count(*) FROM fwapg.proto4_area WHERE downstream_id IS NULL) AS outlets;
