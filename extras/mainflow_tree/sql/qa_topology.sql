-- Splits, cut-offs, dead ends and outlets with no parent inside BC in the
-- main-flow tree, for review and for the tests in qa.sql. Nodes are segment ends snapped to 1 cm; segments are digitized from
-- their downstream end, so a segment's start is its downstream node (dn) and its
-- end its upstream node (up).
--
-- split:   a node that is the upstream node of more than one tree segment (water
--          leaves it by two paths). Every tree segment at the node is listed.
-- cut_off: a tree segment whose downstream node is no tree segment's upstream
--          node, but is some network segment's upstream node: its water continues
--          only through segments the tree dropped.
-- dead_end: a tree segment whose downstream node is no network segment's
--          upstream node, on a line the blue line paths give a parent: the water
--          continues, but the geometry does not (a junction more than 1 cm from
--          the mouth).
-- no_parent: the same, on a line the paths give no parent, with its mouth
--          inside BC (a 50 m circle around it lies within fwa_bcboundary): a gap
--          in the paths or a closed basin. Mouths with no parent within 50 m of
--          BC's edge (the coast or a land border) are outlets and are not listed.
--
-- Computed from the network geometry, independently of how mainflow_tree.sql
-- chose the segments.

CREATE TEMPORARY TABLE qa_nodes AS
SELECT
  s.linear_feature_id,
  s.blue_line_key,
  t.linear_feature_id IS NOT NULL AS in_tree,
  t.source = 'mainflow' AS in_mainflow,
  round(ST_X(ST_StartPoint(s.geom)) * 100)::bigint AS dn_x,
  round(ST_Y(ST_StartPoint(s.geom)) * 100)::bigint AS dn_y,
  round(ST_X(ST_EndPoint(s.geom)) * 100)::bigint AS up_x,
  round(ST_Y(ST_EndPoint(s.geom)) * 100)::bigint AS up_y
FROM whse_basemapping.fwa_stream_networks_sp s
LEFT JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t
  ON t.linear_feature_id = s.linear_feature_id;

CREATE INDEX ON qa_nodes (up_x, up_y);
ANALYZE qa_nodes;

-- tree mouths that touch nothing, on lines the paths give no parent (about
-- 27,000); the BC test below runs on these only
CREATE TEMPORARY TABLE orphan_mouths AS
SELECT n.linear_feature_id, ST_StartPoint(s.geom) AS mouth
FROM qa_nodes n
INNER JOIN whse_basemapping.fwa_stream_networks_sp s ON s.linear_feature_id = n.linear_feature_id
WHERE n.in_tree
AND NOT EXISTS (
  SELECT 1 FROM qa_nodes d
  WHERE d.up_x = n.dn_x AND d.up_y = n.dn_y
)
AND NOT EXISTS (SELECT 1 FROM fwapg.blk_parents p WHERE p.blue_line_key = n.blue_line_key);

DROP TABLE IF EXISTS fwapg.mainflow_tree_qa;

CREATE TABLE fwapg.mainflow_tree_qa AS
WITH split_nodes AS (
  SELECT up_x, up_y
  FROM qa_nodes
  WHERE in_tree
  GROUP BY up_x, up_y
  HAVING count(*) > 1
),
problems AS (
  SELECT n.linear_feature_id, 'split' AS kind
  FROM qa_nodes n
  INNER JOIN split_nodes sn ON sn.up_x = n.up_x AND sn.up_y = n.up_y
  WHERE n.in_tree
  UNION ALL
  SELECT n.linear_feature_id, 'cut_off'
  FROM qa_nodes n
  WHERE n.in_tree
  AND NOT EXISTS (
    SELECT 1 FROM qa_nodes d
    WHERE d.up_x = n.dn_x AND d.up_y = n.dn_y AND d.in_tree
  )
  AND EXISTS (
    SELECT 1 FROM qa_nodes d
    WHERE d.up_x = n.dn_x AND d.up_y = n.dn_y
  )
  UNION ALL
  SELECT n.linear_feature_id, 'dead_end'
  FROM qa_nodes n
  WHERE n.in_tree
  AND NOT EXISTS (
    SELECT 1 FROM qa_nodes d
    WHERE d.up_x = n.dn_x AND d.up_y = n.dn_y
  )
  AND EXISTS (SELECT 1 FROM fwapg.blk_parents p WHERE p.blue_line_key = n.blue_line_key)
  UNION ALL
  SELECT o.linear_feature_id, 'no_parent'
  FROM orphan_mouths o
  WHERE coalesce(ST_Covers(
    (SELECT ST_Union(b.geom) FROM whse_basemapping.fwa_bcboundary b
     WHERE ST_Intersects(b.geom, ST_Buffer(o.mouth, 50))),
    ST_Buffer(o.mouth, 50)), false)
)
SELECT
  p.kind,
  p.linear_feature_id,
  s.watershed_group_code,
  s.blue_line_key,
  s.blue_line_key = s.watershed_key AS mainflow,
  s.edge_type,
  s.downstream_route_measure,
  bp.parent_blue_line_key,
  bp.junction_method,
  bp.junction_gap_m
FROM problems p
INNER JOIN whse_basemapping.fwa_stream_networks_sp s ON s.linear_feature_id = p.linear_feature_id
LEFT JOIN fwapg.blk_parents bp ON bp.blue_line_key = s.blue_line_key;

-- the same counts over the whole network (splits) and over main flow alone
-- (cut-offs): both are thousands, so a zero in the tree is not broken snapping
DROP TABLE IF EXISTS fwapg.mainflow_tree_qa_counts;

CREATE TABLE fwapg.mainflow_tree_qa_counts AS
SELECT
  (SELECT count(*) FROM (
    SELECT 1 FROM qa_nodes GROUP BY up_x, up_y HAVING count(*) > 1
  ) x) AS network_split_nodes,
  (SELECT count(*) FROM qa_nodes n
   WHERE n.in_mainflow
   AND NOT EXISTS (SELECT 1 FROM qa_nodes d WHERE d.up_x = n.dn_x AND d.up_y = n.dn_y AND d.in_mainflow)
   AND EXISTS (SELECT 1 FROM qa_nodes d WHERE d.up_x = n.dn_x AND d.up_y = n.dn_y)
  ) AS mainflow_cut_offs;
