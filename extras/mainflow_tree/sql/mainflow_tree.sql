-- The main-flow tree: a dendritic subset of fwa_stream_networks_sp (fwapg#2).
--
-- FWA maps braids and side channels as secondary flow, so the network splits
-- downstream. Main flow (blue_line_key = watershed_key) does not split, but drops
-- the tributaries whose mouth is on a side channel. The tree is built in four
-- steps:
--
-- 1. mainflow: every segment of every main-flow blue line on the network (codes
--    under 999 are not), all edge types, including subsurface flow (1425) and
--    watershed group connectors (6010).
-- 2. reattached: on each side channel that a main-flow line drains through, the
--    side channel from the point where that water enters down to its mouth. The
--    part above the highest entry is left out, so no split is introduced. Which
--    side channels a line drains through, and where it enters each, comes from
--    the blue line parents (extras/blue_line_paths): walk down from every
--    main-flow line through its parent side channels until main flow is reached;
--    side channels nest, so the walk recurses. A line whose mouth is already on a
--    main-flow node is not walked: its water joins main flow there, and the parent
--    the paths picked (a side channel within 1 m, near its top) would add a split.
-- 3. followed: a tree segment whose water continues only through dropped
--    segments (a cut-off) is extended down the network while there is exactly one
--    way down. This reaches the tree where a parent junction does not touch the
--    line it joins (a gap in the junction, not in the geometry).
-- 4. overrides (overrides.csv): segments excluded or included by hand.
--
-- Nodes are segment ends snapped to 1 cm. Segments are digitized from their
-- downstream end, so a segment's start is its downstream node.

DROP TABLE IF EXISTS whse_basemapping.fwa_stream_networks_mainflow_tree;

CREATE TABLE whse_basemapping.fwa_stream_networks_mainflow_tree (
  linear_feature_id bigint PRIMARY KEY,
  watershed_group_code text,
  blue_line_key integer,
  source text  -- mainflow, reattached, followed, override
);

CREATE TEMPORARY TABLE net_nodes AS
SELECT
  linear_feature_id,
  blue_line_key,
  watershed_group_code,
  round(ST_X(ST_StartPoint(geom)) * 100)::bigint AS dn_x,
  round(ST_Y(ST_StartPoint(geom)) * 100)::bigint AS dn_y,
  round(ST_X(ST_EndPoint(geom)) * 100)::bigint AS up_x,
  round(ST_Y(ST_EndPoint(geom)) * 100)::bigint AS up_y
FROM whse_basemapping.fwa_stream_networks_sp;

ALTER TABLE net_nodes ADD PRIMARY KEY (linear_feature_id);
CREATE INDEX ON net_nodes (up_x, up_y);
CREATE INDEX ON net_nodes (dn_x, dn_y);
ANALYZE net_nodes;

-- 1. main flow
CREATE TEMPORARY TABLE mainflow_blks AS
SELECT DISTINCT blue_line_key
FROM whse_basemapping.fwa_stream_networks_sp
WHERE blue_line_key = watershed_key
AND wscode_ltree IS NOT NULL
AND NOT wscode_ltree <@ '999';

ALTER TABLE mainflow_blks ADD PRIMARY KEY (blue_line_key);
ANALYZE mainflow_blks;

INSERT INTO whse_basemapping.fwa_stream_networks_mainflow_tree
SELECT s.linear_feature_id, s.watershed_group_code, s.blue_line_key, 'mainflow'
FROM whse_basemapping.fwa_stream_networks_sp s
INNER JOIN mainflow_blks m ON m.blue_line_key = s.blue_line_key;

-- 2. lines whose mouth (downstream node of their lowest segment) is the upstream
-- node of a main-flow segment of another line
CREATE TEMPORARY TABLE on_mainflow AS
SELECT DISTINCT mouth.blue_line_key
FROM (
  SELECT DISTINCT ON (s.blue_line_key) s.blue_line_key, n.dn_x, n.dn_y
  FROM whse_basemapping.fwa_stream_networks_sp s
  INNER JOIN net_nodes n ON n.linear_feature_id = s.linear_feature_id
  ORDER BY s.blue_line_key, s.downstream_route_measure
) mouth
INNER JOIN net_nodes n
  ON n.up_x = mouth.dn_x AND n.up_y = mouth.dn_y
  AND n.blue_line_key != mouth.blue_line_key
INNER JOIN mainflow_blks m ON m.blue_line_key = n.blue_line_key;

ALTER TABLE on_mainflow ADD PRIMARY KEY (blue_line_key);

-- each side channel a main-flow line drains through, and the measure on it where
-- that water enters; the walk stops at main flow
CREATE TEMPORARY TABLE side_channel_entries AS
WITH RECURSIVE walk AS (
  SELECT p.parent_blue_line_key AS blue_line_key, p.junction_measure
  FROM fwapg.blk_parents p
  INNER JOIN mainflow_blks m ON m.blue_line_key = p.blue_line_key
  WHERE NOT EXISTS (SELECT 1 FROM mainflow_blks m2 WHERE m2.blue_line_key = p.parent_blue_line_key)
  AND NOT EXISTS (SELECT 1 FROM on_mainflow o WHERE o.blue_line_key = p.blue_line_key)
  UNION
  SELECT p.parent_blue_line_key, p.junction_measure
  FROM walk w
  INNER JOIN fwapg.blk_parents p ON p.blue_line_key = w.blue_line_key
  WHERE NOT EXISTS (SELECT 1 FROM mainflow_blks m2 WHERE m2.blue_line_key = p.parent_blue_line_key)
  AND NOT EXISTS (SELECT 1 FROM on_mainflow o WHERE o.blue_line_key = p.blue_line_key)
)
SELECT blue_line_key, max(junction_measure) AS top_measure
FROM walk
GROUP BY blue_line_key;

-- side channel segments that start below the highest entry (1 cm tolerance: a
-- junction measure located on the geometry lands within float error of the node)
INSERT INTO whse_basemapping.fwa_stream_networks_mainflow_tree
SELECT s.linear_feature_id, s.watershed_group_code, s.blue_line_key, 'reattached'
FROM whse_basemapping.fwa_stream_networks_sp s
INNER JOIN side_channel_entries e ON e.blue_line_key = s.blue_line_key
WHERE s.downstream_route_measure < e.top_measure - 0.01
AND NOT EXISTS (
  SELECT 1 FROM whse_basemapping.fwa_stream_networks_mainflow_tree t
  WHERE t.linear_feature_id = s.linear_feature_id
);

-- 3. follow cut-offs down while there is one way down. The segment added starts
-- at the cut-off's downstream node, which no tree segment starts at, so no split
-- is added.
CREATE TEMPORARY TABLE tree_nodes AS
SELECT n.*
FROM net_nodes n
INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t ON t.linear_feature_id = n.linear_feature_id;

CREATE INDEX ON tree_nodes (up_x, up_y);
CREATE INDEX ON tree_nodes (linear_feature_id);
ANALYZE tree_nodes;

-- cut-offs: tree segments whose downstream node no tree segment starts at, but
-- some network segment does
CREATE TEMPORARY TABLE frontier AS
SELECT c.*
FROM tree_nodes c
WHERE NOT EXISTS (SELECT 1 FROM tree_nodes t WHERE t.up_x = c.dn_x AND t.up_y = c.dn_y)
AND EXISTS (SELECT 1 FROM net_nodes e WHERE e.up_x = c.dn_x AND e.up_y = c.dn_y);

CREATE TEMPORARY TABLE next_segments (LIKE net_nodes);

DO $$
DECLARE
  r integer := 0;
  n integer;
BEGIN
  LOOP
    r := r + 1;
    TRUNCATE next_segments;
    INSERT INTO next_segments
    SELECT DISTINCT d.*
    FROM frontier c
    INNER JOIN net_nodes d ON d.up_x = c.dn_x AND d.up_y = c.dn_y
    WHERE (SELECT count(*) FROM net_nodes e WHERE e.up_x = c.dn_x AND e.up_y = c.dn_y) = 1
    AND NOT EXISTS (SELECT 1 FROM tree_nodes t WHERE t.up_x = c.dn_x AND t.up_y = c.dn_y)
    AND NOT EXISTS (SELECT 1 FROM tree_nodes t WHERE t.linear_feature_id = d.linear_feature_id);
    GET DIAGNOSTICS n = ROW_COUNT;
    EXIT WHEN n = 0;
    IF r > 1000 THEN
      RAISE EXCEPTION 'following cut-offs did not stop in 1000 rounds';
    END IF;

    INSERT INTO whse_basemapping.fwa_stream_networks_mainflow_tree
    SELECT linear_feature_id, watershed_group_code, blue_line_key, 'followed'
    FROM next_segments;
    INSERT INTO tree_nodes SELECT * FROM next_segments;

    TRUNCATE frontier;
    INSERT INTO frontier
    SELECT c.*
    FROM next_segments c
    WHERE NOT EXISTS (SELECT 1 FROM tree_nodes t WHERE t.up_x = c.dn_x AND t.up_y = c.dn_y);
  END LOOP;
END $$;

-- 4. overrides, loaded by mainflow_tree.sh into fwapg.mainflow_tree_overrides
DELETE FROM whse_basemapping.fwa_stream_networks_mainflow_tree t
USING fwapg.mainflow_tree_overrides o
WHERE o.linear_feature_id = t.linear_feature_id
AND o.action = 'exclude';

INSERT INTO whse_basemapping.fwa_stream_networks_mainflow_tree
SELECT s.linear_feature_id, s.watershed_group_code, s.blue_line_key, 'override'
FROM fwapg.mainflow_tree_overrides o
INNER JOIN whse_basemapping.fwa_stream_networks_sp s ON s.linear_feature_id = o.linear_feature_id
WHERE o.action = 'include'
ON CONFLICT (linear_feature_id) DO NOTHING;

CREATE INDEX ON whse_basemapping.fwa_stream_networks_mainflow_tree (blue_line_key);
CREATE INDEX ON whse_basemapping.fwa_stream_networks_mainflow_tree (watershed_group_code);
ANALYZE whse_basemapping.fwa_stream_networks_mainflow_tree;
