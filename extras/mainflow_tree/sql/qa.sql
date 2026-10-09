-- QA tests for the main-flow tree, all should return result = t. Run after
-- qa_topology.sql; mainflow_tree.sh stops before export if any is f.

SELECT 'the tree has main-flow, reattached and followed segments' AS test,
  count(DISTINCT source) FILTER (WHERE source IN ('mainflow', 'reattached', 'followed')) = 3 AS result
FROM whse_basemapping.fwa_stream_networks_mainflow_tree;

SELECT 'the topology checks find splits in the network and cut-offs in main flow alone' AS test,
  network_split_nodes > 1000 AND mainflow_cut_offs > 1000 AS result
FROM fwapg.mainflow_tree_qa_counts;

SELECT 'no splits' AS test,
  NOT EXISTS (SELECT 1 FROM fwapg.mainflow_tree_qa WHERE kind = 'split') AS result;

-- the ceiling is the 2026-10 province-wide count (README): each is a reattached
-- side channel whose downstream node has two ways down, which the following
-- step does not choose between
SELECT 'at most 8 cut-off segments' AS test,
  count(*) <= 8 AS result
FROM fwapg.mainflow_tree_qa
WHERE kind = 'cut_off';

-- the ceiling is the 2026-10 province-wide count (README): 354 main stems whose
-- mouth is off their code junction, 119 side channels reached by a fallback
-- junction. Gaps in the geometry, which no choice of segments closes.
SELECT 'at most 473 dead ends' AS test,
  count(*) <= 473 AS result
FROM fwapg.mainflow_tree_qa
WHERE kind = 'dead_end';

-- the edge type 1450 connectors a hand-built Skeena network had to add back
-- (fwapg#2): 24 are main flow, 360222215 and 360237491 are side channels
SELECT 'the 26 Skeena 1450 connectors are in the tree at measure 0' AS test,
  count(DISTINCT s.blue_line_key) = 26 AS result
FROM whse_basemapping.fwa_stream_networks_sp s
INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t ON t.linear_feature_id = s.linear_feature_id
WHERE s.downstream_route_measure = 0
AND s.edge_type = 1450
AND s.blue_line_key IN (
  360883243, 360222215, 360237491, 360881231, 360884603, 360422693, 360879488,
  360768563, 360397147, 360869584, 360873822, 360850339, 360885864, 360886970,
  360678242, 360814623, 360816333, 360886207, 360885316, 360886221, 360882037,
  360801822, 360887063, 360715518, 360884191, 360859802
);

-- tributaries whose mouth is on a Skeena side channel reach main flow through the
-- side channel below the entry point (fwapg#2, flow direction table): each side
-- channel is kept from measure 0 through the entry. It can be kept higher, where
-- other water from main flow enters it further up (360216952, to 1699.6), but
-- never above its highest entry (by construction).
WITH expected (side_channel, entry) AS (
  VALUES
    (360222215, 297.7),   -- 360883243 enters
    (360237491, 325.3),   -- 360881231 enters
    (360222216, 1386.5),  -- 360222215's mouth enters
    (360216952, 1017.0)   -- 360884603 enters
),
kept AS (
  SELECT
    e.side_channel,
    e.entry,
    min(s.downstream_route_measure) AS bottom,
    max(s.downstream_route_measure + s.length_metre) AS top,
    sum(s.length_metre) AS kept_length
  FROM expected e
  INNER JOIN whse_basemapping.fwa_stream_networks_sp s ON s.blue_line_key = e.side_channel
  INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t ON t.linear_feature_id = s.linear_feature_id
  GROUP BY e.side_channel, e.entry
)
SELECT 'four Skeena side channels are kept from 0 through the tributary entry' AS test,
  count(*) = 4 AND bool_and(bottom = 0 AND top > entry - 1 AND abs(kept_length - top) < 0.01) AS result
FROM kept;

SELECT 'the three Skeena tributaries that enter side channels are in the tree' AS test,
  count(DISTINCT s.blue_line_key) = 3 AS result
FROM whse_basemapping.fwa_stream_networks_sp s
INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t ON t.linear_feature_id = s.linear_feature_id
WHERE s.blue_line_key IN (360883243, 360881231, 360884603)
AND s.downstream_route_measure = 0;

-- a hand-built Nechako network needed a side-channel path added back for this
-- (fwapg#2): every line on the Chilako's path down to the Nechako is in the tree,
-- and none of their segments is cut off
WITH chilako AS (
  SELECT DISTINCT blue_line_key FROM whse_basemapping.fwa_stream_networks_sp
  WHERE wscode_ltree = '100.567134.069486' AND blue_line_key = watershed_key
),
nechako AS (
  SELECT DISTINCT blue_line_key FROM whse_basemapping.fwa_stream_networks_sp
  WHERE wscode_ltree = '100.567134' AND blue_line_key = watershed_key
),
path AS (
  -- the Chilako and the lines on its path below it, up to the Nechako
  SELECT c.blue_line_key, u.blk, u.i
  FROM chilako c
  INNER JOIN fwapg.blk_paths p ON p.blue_line_key = c.blue_line_key
  CROSS JOIN LATERAL unnest(p.path_blks) WITH ORDINALITY AS u(blk, i)
),
upto AS (
  SELECT p.blk
  FROM path p
  WHERE p.i < (SELECT min(q.i) FROM path q WHERE q.blk IN (SELECT blue_line_key FROM nechako))
  UNION
  SELECT blue_line_key FROM chilako
)
SELECT 'the Chilako reaches the Nechako through the tree' AS test,
  (SELECT count(*) FROM chilako) = 1
  AND EXISTS (SELECT 1 FROM path WHERE blk IN (SELECT blue_line_key FROM nechako))
  AND NOT EXISTS (
    SELECT 1 FROM upto u
    WHERE NOT EXISTS (
      SELECT 1
      FROM whse_basemapping.fwa_stream_networks_sp s
      INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t ON t.linear_feature_id = s.linear_feature_id
      WHERE s.blue_line_key = u.blk AND s.downstream_route_measure = 0
    )
  )
  AND NOT EXISTS (
    SELECT 1 FROM fwapg.mainflow_tree_qa q
    WHERE q.blue_line_key IN (SELECT blk FROM upto)
  ) AS result;
