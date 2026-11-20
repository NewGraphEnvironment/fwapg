-- QA tests for the main-flow tree, all should return result = t. Run after
-- qa_topology.sql, mainflow_tree_area.sql and qa_area.sql, in that order, as
-- mainflow_tree.sh does (run after a rebuild of one of them alone, the tests
-- read the others' tables from the build before); mainflow_tree.sh stops before
-- export if any is f.

SELECT 'the tree has main-flow, reattached and followed segments' AS test,
  count(DISTINCT source) FILTER (WHERE source IN ('mainflow', 'reattached', 'followed')) = 3 AS result
FROM whse_basemapping.fwa_stream_networks_mainflow_tree;

SELECT 'the topology checks find splits in the network and cut-offs in main flow alone' AS test,
  network_split_nodes > 1000 AND mainflow_cut_offs > 1000 AS result
FROM fwapg.mainflow_tree_qa_counts;

SELECT 'no splits' AS test,
  NOT EXISTS (SELECT 1 FROM fwapg.mainflow_tree_qa WHERE kind = 'split') AS result;

-- the ceiling is the 2026-10 province-wide count (README): each is a segment
-- added by following whose downstream node has two ways down, which following
-- does not choose between
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

-- the ceiling is the 2026-10 province-wide count (README): mouths that touch
-- nothing, inside BC, on lines the paths give no parent (11 main-flow lines,
-- 12 side channels)
SELECT 'at most 23 outlets with no parent inside BC' AS test,
  count(*) <= 23 AS result
FROM fwapg.mainflow_tree_qa
WHERE kind = 'no_parent';

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

-- Upstream area (mainflow_tree_area.sql, fwapg#4). Each test below is one
-- aggregate with no GROUP BY, so it always prints a line.

SELECT 'every tree segment has a positive upstream area' AS test,
  count(*) > 0
  AND count(*) FILTER (WHERE t.upstream_area_ha > 0) = count(*)
  AND count(*) FILTER (WHERE a.upstream_area_ha IS NOT DISTINCT FROM t.upstream_area_ha) = count(*) AS result
FROM whse_basemapping.fwa_stream_networks_mainflow_tree t
LEFT JOIN fwapg.mainflow_tree_area a ON a.linear_feature_id = t.linear_feature_id;

-- what flows into a segment is taken from the network geometry here (the tree
-- segments whose downstream node is its upstream node, nodes at 1 cm, as in
-- qa_topology.sql), not from the pointer the area was summed along; only the
-- steps across a gap, which geometry cannot give, are read from the table
WITH nodes AS (
  SELECT
    t.linear_feature_id,
    t.upstream_area_ha,
    round(ST_X(ST_StartPoint(s.geom)) * 100)::bigint AS dn_x,
    round(ST_Y(ST_StartPoint(s.geom)) * 100)::bigint AS dn_y,
    round(ST_X(ST_EndPoint(s.geom)) * 100)::bigint AS up_x,
    round(ST_Y(ST_EndPoint(s.geom)) * 100)::bigint AS up_y
  FROM whse_basemapping.fwa_stream_networks_sp s
  INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t ON t.linear_feature_id = s.linear_feature_id
),
inflow AS (
  SELECT b.linear_feature_id, a.upstream_area_ha
  FROM nodes a
  INNER JOIN nodes b ON b.up_x = a.dn_x AND b.up_y = a.dn_y AND b.linear_feature_id != a.linear_feature_id
  UNION ALL
  SELECT g.downstream_id, g.upstream_area_ha
  FROM fwapg.mainflow_tree_area g
  WHERE g.downstream_method IN ('line', 'junction')
),
total AS (
  SELECT linear_feature_id, sum(upstream_area_ha) AS area_ha
  FROM inflow
  GROUP BY linear_feature_id
)
SELECT 'area is additive at every node: local area plus what flows in' AS test,
  count(*) > 0
  AND count(*) FILTER (
    WHERE abs(a.upstream_area_ha - a.local_area_ha - coalesce(i.area_ha, 0)) <= 1e-9 * greatest(a.upstream_area_ha, 1)
  ) = count(*) AS result
FROM fwapg.mainflow_tree_area a
LEFT JOIN total i ON i.linear_feature_id = a.linear_feature_id;

-- along a blue line, by measure: where two tree segments of a line touch, the
-- lower one carries at least the upper one's area
-- (2,967,528 touching pairs in the 2026-11 build; the floor shows the test saw them)
WITH line AS (
  SELECT
    t.upstream_area_ha,
    s.downstream_route_measure AS drm,
    lag(t.upstream_area_ha) OVER w AS lower_area_ha,
    lag(s.downstream_route_measure + s.length_metre) OVER w AS lower_top
  FROM whse_basemapping.fwa_stream_networks_sp s
  INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t ON t.linear_feature_id = s.linear_feature_id
  WINDOW w AS (PARTITION BY s.blue_line_key ORDER BY s.downstream_route_measure)
)
SELECT 'area never decreases downstream along a blue line' AS test,
  count(*) FILTER (WHERE abs(lower_top - drm) < 0.01) > 2000000
  AND count(*) FILTER (
    WHERE abs(lower_top - drm) < 0.01
    AND lower_area_ha < upstream_area_ha - 1e-9 * greatest(upstream_area_ha, 1)
  ) = 0 AS result
FROM line;

-- nothing is lost or added on the way down: the areas at the tree's outlets sum
-- to the polygons given to a segment, plus what streams with no polygon of their
-- own were given out of polygons the codes give to no segment
SELECT 'the outlets'' areas sum to the area assigned' AS test,
  abs(
    (SELECT sum(upstream_area_ha) FROM fwapg.mainflow_tree_area WHERE downstream_id IS NULL)
    - (SELECT sum(CASE WHEN linear_feature_id IS NOT NULL THEN area_ha ELSE shared_ha END) FROM fwapg.mainflow_tree_area_polygons)
  ) <= 1e-9 * (SELECT sum(area_ha) FROM fwapg.mainflow_tree_area_polygons) AS result;

-- the ceilings are the 2026-11 counts (README): polygons whose watershed code
-- and every ancestor of it are on no tree segment, those under 999, and those
-- below the lowest tree segment of their stream. Each class is the property it
-- names (mainflow_tree_area.sql), so a polygon a rule should have placed has none.
SELECT 'every unassigned polygon has a class: at most 53,208 with no stream, 60 under 999, 3 below the tree' AS test,
  count(*) > 0
  AND count(*) FILTER (WHERE class IS NULL) = 0
  AND count(*) FILTER (WHERE class = 'no stream') <= 53208
  AND count(*) FILTER (WHERE class = '999') <= 60
  AND count(*) FILTER (WHERE class = 'below the tree') <= 3
  AND count(*) FILTER (WHERE class NOT IN ('no stream', '999', 'below the tree')) = 0 AS result
FROM fwapg.mainflow_tree_area_unassigned;

-- a step across a gap (line, junction) starts only at a dead end or cut-off the
-- topology QA found from geometry, none of those has a node step, and a segment
-- with no step at all is an outlet: at most the 383 dead ends and 1 cut-off the
-- paths lead nowhere from, and the mouths with no parent
SELECT 'steps across a gap start at dead ends and cut-offs only' AS test,
  count(*) FILTER (WHERE a.downstream_method IN ('line', 'junction')) > 0
  AND count(*) FILTER (WHERE a.downstream_method IN ('line', 'junction') AND q.kind IS NULL) = 0
  AND count(*) FILTER (WHERE a.downstream_method = 'node' AND q.kind IS NOT NULL) = 0
  AND count(*) FILTER (WHERE a.downstream_id IS NULL AND q.kind = 'dead_end') <= 383
  AND count(*) FILTER (WHERE a.downstream_id IS NULL AND q.kind = 'cut_off') <= 1 AS result
FROM fwapg.mainflow_tree_area a
LEFT JOIN (
  SELECT DISTINCT linear_feature_id, kind FROM fwapg.mainflow_tree_qa WHERE kind IN ('dead_end', 'cut_off')
) q ON q.linear_feature_id = a.linear_feature_id;

-- independent of the pointer and of which segment a polygon was given to: a
-- basin's area at its mouth against the polygons under its watershed code. Not
-- equal: steps across a gap bring in streams of another code, and a dead end
-- inside the basin keeps its area (0.003% and 0.004% in the 2026-11 build).
WITH basin (name, code) AS (
  VALUES ('Skeena', '400'::ltree), ('Nechako', '100.567134'::ltree)
),
mouth AS (
  SELECT b.name, b.code, (
    SELECT t.upstream_area_ha
    FROM whse_basemapping.fwa_stream_networks_sp s
    INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t ON t.linear_feature_id = s.linear_feature_id
    WHERE s.wscode_ltree = b.code AND s.blue_line_key = s.watershed_key
    ORDER BY s.downstream_route_measure
    LIMIT 1
  ) AS tree_ha, (
    SELECT sum(ST_Area(w.geom)) / 10000
    FROM whse_basemapping.fwa_watersheds_poly w
    WHERE w.wscode_ltree <@ b.code
  ) AS polygons_ha
  FROM basin b
)
SELECT 'the Skeena and the Nechako carry the polygons under their code at their mouth, within 0.01%' AS test,
  -- counted, not bool_and(): a basin with no mouth or no polygons gives NULL,
  -- which bool_and() would skip
  count(*) FILTER (WHERE abs(tree_ha - polygons_ha) <= 1e-4 * polygons_ha) = 2 AS result
FROM mouth;

-- the test side channels (fwapg#4): below where the tributary enters, each
-- carries the tributary's area (the polygons under the tributary's code: 51,420,
-- 228,943 and 302,611 ha) and at most 5% more from its own polygons and other
-- water entering it, where the lookup gave it the Skeena's 4 to 5 million ha
WITH expected (side_channel, entry, tributary) AS (
  VALUES
    (360222215, 297.7, '400.195432'::ltree),
    (360237491, 325.3, '400.221484'::ltree),
    (360222216, 1386.5, '400.195432'::ltree),
    (360216952, 1017.0, '400.107640'::ltree)
),
measured AS (
  SELECT e.side_channel, (
    SELECT t.upstream_area_ha
    FROM whse_basemapping.fwa_stream_networks_sp s
    INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t ON t.linear_feature_id = s.linear_feature_id
    WHERE s.blue_line_key = e.side_channel AND s.downstream_route_measure < e.entry - 1
    ORDER BY s.downstream_route_measure DESC
    LIMIT 1
  ) AS area_ha, (
    SELECT sum(ST_Area(w.geom)) / 10000
    FROM whse_basemapping.fwa_watersheds_poly w
    WHERE w.wscode_ltree <@ e.tributary
  ) AS tributary_ha
  FROM expected e
)
SELECT 'four Skeena side channels carry the area of the tributary entering them' AS test,
  count(*) FILTER (
    WHERE tributary_ha > 50000 AND area_ha >= 0.999 * tributary_ha AND area_ha <= 1.05 * tributary_ha
  ) = 4 AS result
FROM measured;

-- 360881231's mouth connector lies in a Skeena polygon, and the lookup gives it
-- 4,558,110 ha
SELECT 'a tributary mouth inside its river''s polygon carries the tributary''s area' AS test,
  count(*) = 1
  AND coalesce(bool_and(abs(t.upstream_area_ha - (
    SELECT sum(ST_Area(w.geom)) / 10000
    FROM whse_basemapping.fwa_watersheds_poly w
    WHERE w.wscode_ltree <@ '400.221484'
  )) <= 1e-3 * t.upstream_area_ha), false) AS result
FROM whse_basemapping.fwa_stream_networks_mainflow_tree t
WHERE t.linear_feature_id = 87078680;

-- each polygon is on a segment its rule allows, read from the polygon's and the
-- segment's codes (mainflow_tree_area.sql's header has the rules). Only
-- pair_side may put a polygon on a side channel: a side channel carries what
-- enters it and the polygons that are its own by their codes.
SELECT 'every polygon is on a segment its rule allows, and only pair_side on a side channel' AS test,
  count(*) FILTER (WHERE p.method = 'pair') > 3000000
  AND count(*) FILTER (WHERE p.method = 'pair_side') > 0
  AND count(*) FILTER (WHERE p.method = 'range') > 0
  AND count(*) FILTER (WHERE p.method = 'lower') > 0
  AND count(*) FILTER (WHERE p.method = 'ancestor') > 0
  AND count(*) FILTER (WHERE (
    CASE p.method
      WHEN 'pair' THEN t.source = 'mainflow' AND s.wscode_ltree = w.wscode_ltree AND s.localcode_ltree >= w.code
      WHEN 'pair_side' THEN t.source != 'mainflow' AND s.wscode_ltree = w.wscode_ltree AND s.localcode_ltree = w.code
      WHEN 'range' THEN t.source = 'mainflow' AND s.wscode_ltree = w.wscode_ltree AND s.localcode_ltree > w.code
      WHEN 'lower' THEN t.source = 'mainflow' AND s.wscode_ltree = w.wscode_ltree AND s.localcode_ltree < w.code
      WHEN 'ancestor' THEN t.source = 'mainflow' AND w.wscode_ltree <@ s.wscode_ltree AND w.wscode_ltree != s.wscode_ltree
        AND s.localcode_ltree < subpath(w.wscode_ltree, 0, nlevel(s.wscode_ltree) + 1)
    END) IS NOT TRUE) = 0 AS result
FROM fwapg.mainflow_tree_area_polygons p
INNER JOIN (
  SELECT watershed_feature_id, wscode_ltree,
    CASE WHEN localcode_ltree <@ wscode_ltree THEN localcode_ltree ELSE wscode_ltree END AS code
  FROM whse_basemapping.fwa_watersheds_poly
) w ON w.watershed_feature_id = p.watershed_feature_id
INNER JOIN whse_basemapping.fwa_stream_networks_sp s ON s.linear_feature_id = p.linear_feature_id
INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t ON t.linear_feature_id = p.linear_feature_id
WHERE p.linear_feature_id IS NOT NULL;

-- the ceilings are the 2026-11 counts (README): steps across a gap, and segments
-- with nothing above them that were given a length share of the polygon they lie in
-- A segment that gives a share keeps what is left of the polygon; where the
-- shares are the whole polygon that is float noise, which must not be the
-- segment's whole area (it would read as positive).
SELECT 'at most 97 steps across a gap and 803 segments given a length share' AS test,
  (SELECT count(*) FROM fwapg.mainflow_tree_area WHERE downstream_method IN ('line', 'junction')) BETWEEN 1 AND 97
  AND (SELECT count(*) FROM fwapg.mainflow_tree_area_shares) BETWEEN 1 AND 803
  AND (SELECT count(*) FROM fwapg.mainflow_tree_area WHERE shared_area_ha > 0)
    = (SELECT count(*) FROM fwapg.mainflow_tree_area_shares)
  AND (SELECT count(*) FROM fwapg.mainflow_tree_area WHERE shared_area_ha < 0 AND upstream_area_ha < 1e-6) = 0 AS result;

-- Against the lookup (qa_area.sql). Where a main-flow segment's lookup polygon
-- has both its codes and nothing upstream is routed differently by the tree than
-- by the codes, the two areas are equal: every difference there has a class
-- (a code anomaly on the segment, or a lookup row that is not what its own
-- definition gives), bar 17 segments on 11 lines in the 2026-11 build that are
-- not explained (README). The floors show the comparison saw the tree.
SELECT 'main flow agrees with the lookup where nothing upstream is routed differently, bar at most 17 segments' AS test,
  (SELECT comparable > 4000000 AND routed_alike > 4000000 FROM fwapg.mainflow_tree_area_qa_counts)
  AND (SELECT count(*) FROM fwapg.mainflow_tree_area_qa WHERE class IS NULL) <= 17 AS result;

-- the comparison can fail: it finds every reattached and followed segment (the
-- lookup gives a side channel its river's area), and where it says something is
-- routed differently the areas do differ (99.6% in the 2026-11 build)
SELECT 'the lookup differs on side channels and where the tree routes differently' AS test,
  (SELECT count(*) FROM fwapg.mainflow_tree_area_qa WHERE source != 'mainflow')
    > 0.99 * (SELECT count(*) FROM whse_basemapping.fwa_stream_networks_mainflow_tree WHERE source != 'mainflow')
  AND (SELECT routed_differently > 50000 AND routed_differently_and_differ > 0.99 * routed_differently
       FROM fwapg.mainflow_tree_area_qa_counts) AS result;

-- the ceilings are the 2026-11 counts (README) of the classes that are not about
-- routing, so a regression cannot hide in one of them
SELECT 'the classes that are not about routing are no larger than measured' AS test,
  count(*) > 0
  AND count(*) FILTER (WHERE class = 'lookup polygon at another local code') <= 53560
  AND count(*) FILTER (WHERE class = 'lookup polygon on another stream') <= 7588
  AND count(*) FILTER (WHERE class = 'no lookup row') <= 2353
  AND count(*) FILTER (WHERE class = 'local codes out of order') <= 878
  AND count(*) FILTER (WHERE class = 'segment local code more than one level deep') <= 138
  AND count(*) FILTER (WHERE class = 'segment local code not under its watershed code') <= 27
  AND count(*) FILTER (WHERE class = 'lookup row is not what its definition gives') <= 155 AS result
FROM fwapg.mainflow_tree_area_qa;
