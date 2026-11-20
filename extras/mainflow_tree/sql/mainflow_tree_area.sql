-- Upstream area for every segment of the main-flow tree: the land whose water
-- passes the segment's downstream end, routed along the tree (fwapg#4). Run
-- after mainflow_tree.sql.
--
-- Each fundamental watershed polygon is given to one tree segment and the
-- polygons' areas are summed down the tree, so area is additive at every
-- confluence, which a spatial stream network model's additive function assumes.
-- The lookup (fwa_streams_watersheds_lut with fwa_watersheds_upstream_area)
-- cannot give that on the tree: a side channel carries its river's watershed
-- code, so the lookup gives it the river's area.
--
-- Which segment a polygon goes to follows the lookup's convention (area at the
-- polygon's outlet), so that plain main flow agrees with it. In FWA_Upstream's
-- terms, in order:
--   1. pair:      a polygon whose codes (watershed code, local code) are on
--                 main-flow segments goes to the top of the lowest run of
--                 main-flow segments on its watershed code whose local code is
--                 at or above its own and below the next local code that has a
--                 polygon. A reach with no polygon of its own so takes the
--                 polygon below it on its stream, which it lies in.
--   2. pair_side: a polygon whose codes are on reattached or followed segments
--                 only goes to the top one of them.
--   3. lower:     failing both, the top segment of the reach on its watershed
--                 code at the greatest local code at or below its own.
--   4. ancestor:  failing that, on its nearest ancestor code in the tree, the
--                 top segment of the reach at the greatest local code strictly
--                 below the code of the branch it lies on (a tributary is not
--                 upstream of the reach that starts at its own junction).
-- A polygon none of these places is listed in fwapg.mainflow_tree_area_unassigned.
--
-- A segment with nothing above it after that lies in another stream's polygon
-- (a stream with no polygon of its own). It takes a share of the polygon at its
-- midpoint, in proportion to its length against the length of all tree segments
-- in that polygon, taken from the segment the polygon was given to. The share
-- is an estimate, kept apart in shared_area_ha.
--
-- Area follows the tree's own nodes (segment ends at 1 cm; a segment's start is
-- its downstream node). Where a tree segment's downstream node is no tree
-- segment's upstream node (a cut-off or a dead end, qa_topology.sql), area is
-- carried to the nearest tree segment lower on its blue line (line) or to the
-- first line on its blue line path with a tree segment below the junction
-- (junction). Where the paths lead to no tree segment, the segment is an outlet.

-- 1. tree segments with their nodes and codes
CREATE TEMPORARY TABLE area_seg AS
SELECT
  s.linear_feature_id,
  s.blue_line_key,
  s.downstream_route_measure AS drm,
  s.length_metre,
  s.wscode_ltree,
  s.localcode_ltree,
  t.source,
  round(ST_X(ST_StartPoint(s.geom)) * 100)::bigint AS dn_x,
  round(ST_Y(ST_StartPoint(s.geom)) * 100)::bigint AS dn_y,
  round(ST_X(ST_EndPoint(s.geom)) * 100)::bigint AS up_x,
  round(ST_Y(ST_EndPoint(s.geom)) * 100)::bigint AS up_y
FROM whse_basemapping.fwa_stream_networks_sp s
INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t ON t.linear_feature_id = s.linear_feature_id;

ALTER TABLE area_seg ADD PRIMARY KEY (linear_feature_id);
-- one tree segment per upstream node, or the tree splits and the build stops here
CREATE UNIQUE INDEX ON area_seg (up_x, up_y);
CREATE INDEX ON area_seg (blue_line_key, drm);
ANALYZE area_seg;

-- 2. each segment's downstream segment. The 1 mm is the tolerance the blue line
-- paths use: a junction measure located on the geometry can land a fraction of
-- a mm off the node it names.
CREATE TEMPORARY TABLE area_down AS
SELECT
  s.linear_feature_id,
  n.linear_feature_id AS downstream_id,
  CASE WHEN n.linear_feature_id IS NOT NULL THEN 'node' END AS downstream_method
FROM area_seg s
LEFT JOIN area_seg n
  ON n.up_x = s.dn_x AND n.up_y = s.dn_y AND n.linear_feature_id != s.linear_feature_id;

-- the segments with no node step (about 27,000, most of them outlets at BC's
-- edge): the segment's own line below it, then each line on its path below the
-- junction
UPDATE area_down d
SET
  downstream_id = j.linear_feature_id,
  downstream_method = CASE WHEN j.step = 0 THEN 'line' ELSE 'junction' END
FROM area_seg s
CROSS JOIN LATERAL (
  SELECT t.linear_feature_id, u.step
  FROM (
    SELECT s.blue_line_key AS blk, s.drm AS measure, 0::bigint AS step
    UNION ALL
    SELECT u.blk, u.measure, u.step
    FROM fwapg.blk_paths bp
    CROSS JOIN LATERAL unnest(bp.path_blks, bp.path_measures) WITH ORDINALITY AS u(blk, measure, step)
    WHERE bp.blue_line_key = s.blue_line_key
  ) u
  CROSS JOIN LATERAL (
    SELECT t.linear_feature_id
    FROM area_seg t
    WHERE t.blue_line_key = u.blk
    AND t.drm < u.measure - 0.001
    ORDER BY t.drm DESC
    LIMIT 1
  ) t
  ORDER BY u.step
  LIMIT 1
) j
WHERE d.downstream_id IS NULL
AND s.linear_feature_id = d.linear_feature_id;

ALTER TABLE area_down ADD PRIMARY KEY (linear_feature_id);
CREATE INDEX ON area_down (downstream_id);
ANALYZE area_down;

-- 3. the polygons, with their area as the lookup sums it (ST_Area, not the
-- area_ha attribute). A polygon with no local code sits at its stream's mouth.
CREATE TEMPORARY TABLE area_poly AS
SELECT
  w.watershed_feature_id,
  w.wscode_ltree,
  coalesce(w.localcode_ltree, w.wscode_ltree) AS localcode_ltree,
  ST_Area(w.geom) / 10000 AS area_ha
FROM whse_basemapping.fwa_watersheds_poly w;

ALTER TABLE area_poly ADD PRIMARY KEY (watershed_feature_id);

CREATE TEMPORARY TABLE area_poly_codes AS
SELECT DISTINCT wscode_ltree, localcode_ltree
FROM area_poly
WHERE wscode_ltree IS NOT NULL
AND NOT wscode_ltree <@ '999'::ltree;

ALTER TABLE area_poly_codes ADD PRIMARY KEY (wscode_ltree, localcode_ltree);
ANALYZE area_poly;
ANALYZE area_poly_codes;

-- 4. rule 1's target per code pair. Each main-flow segment belongs to the
-- greatest local code with a polygon at or below its own (grp); segments of one
-- grp that follow each other up a line are a run. A pair that reappears further
-- up a line (local codes are not always in order) would otherwise pull its
-- polygon up there, so the run taken is one that holds the pair itself, the
-- lowest if there are several.
CREATE TEMPORARY TABLE area_pair_top AS
WITH grouped AS (
  SELECT s.linear_feature_id, s.blue_line_key, s.drm, s.wscode_ltree, s.localcode_ltree, g.localcode_ltree AS grp
  FROM area_seg s
  LEFT JOIN LATERAL (
    SELECT c.localcode_ltree
    FROM area_poly_codes c
    WHERE c.wscode_ltree = s.wscode_ltree
    AND c.localcode_ltree <= s.localcode_ltree
    ORDER BY c.localcode_ltree DESC
    LIMIT 1
  ) g ON true
  WHERE s.source = 'mainflow'
),
started AS (
  SELECT *,
    (grp IS DISTINCT FROM lag(grp) OVER w OR wscode_ltree IS DISTINCT FROM lag(wscode_ltree) OVER w)::integer AS starts
  FROM grouped
  WINDOW w AS (PARTITION BY blue_line_key ORDER BY drm)
),
numbered AS (
  SELECT *, sum(starts) OVER (PARTITION BY blue_line_key ORDER BY drm) AS run
  FROM started
),
runs AS (
  SELECT
    wscode_ltree,
    grp AS localcode_ltree,
    blue_line_key,
    min(drm) AS bottom,
    (array_agg(linear_feature_id ORDER BY drm DESC))[1] AS linear_feature_id,
    bool_or(localcode_ltree = grp) AS has_pair
  FROM numbered
  WHERE grp IS NOT NULL
  GROUP BY wscode_ltree, grp, blue_line_key, run
)
SELECT DISTINCT ON (wscode_ltree, localcode_ltree)
  wscode_ltree, localcode_ltree, linear_feature_id
FROM runs
WHERE has_pair
ORDER BY wscode_ltree, localcode_ltree, bottom, blue_line_key;

ALTER TABLE area_pair_top ADD PRIMARY KEY (wscode_ltree, localcode_ltree);
ANALYZE area_pair_top;

-- the top segment of each reach (code pair) of the tree, for rules 2 to 4:
-- main flow before reattached before the rest
CREATE TEMPORARY TABLE area_reach AS
SELECT DISTINCT ON (wscode_ltree, localcode_ltree)
  wscode_ltree, localcode_ltree, linear_feature_id
FROM area_seg
WHERE localcode_ltree IS NOT NULL
ORDER BY wscode_ltree, localcode_ltree,
  CASE source WHEN 'mainflow' THEN 1 WHEN 'reattached' THEN 2 ELSE 3 END,
  blue_line_key, drm DESC, linear_feature_id;

ALTER TABLE area_reach ADD PRIMARY KEY (wscode_ltree, localcode_ltree);
ANALYZE area_reach;

-- 5. each polygon to one segment
DROP TABLE IF EXISTS fwapg.mainflow_tree_area_polygons;

CREATE TABLE fwapg.mainflow_tree_area_polygons AS
SELECT
  p.watershed_feature_id,
  coalesce(m.linear_feature_id, a.linear_feature_id) AS linear_feature_id,
  CASE
    WHEN m.linear_feature_id IS NOT NULL THEN 'pair'
    WHEN a.levels_up = 0 AND a.localcode_ltree = p.localcode_ltree THEN 'pair_side'
    WHEN a.levels_up = 0 THEN 'lower'
    WHEN a.levels_up > 0 THEN 'ancestor'
  END AS method,
  p.area_ha,
  0::double precision AS shared_ha
FROM area_poly p
LEFT JOIN area_pair_top m
  ON m.wscode_ltree = p.wscode_ltree AND m.localcode_ltree = p.localcode_ltree
LEFT JOIN LATERAL (
  SELECT x.linear_feature_id, x.localcode_ltree, x.levels_up
  FROM (
    (SELECT r.linear_feature_id, r.localcode_ltree, 0 AS levels_up
     FROM area_reach r
     WHERE r.wscode_ltree = p.wscode_ltree
     AND r.localcode_ltree <= p.localcode_ltree
     ORDER BY r.localcode_ltree DESC
     LIMIT 1)
    UNION ALL
    SELECT r.linear_feature_id, r.localcode_ltree, nlevel(p.wscode_ltree) - g.n
    FROM generate_series(nlevel(p.wscode_ltree) - 1, 1, -1) AS g(n)
    CROSS JOIN LATERAL (
      SELECT r.linear_feature_id, r.localcode_ltree
      FROM area_reach r
      WHERE r.wscode_ltree = subpath(p.wscode_ltree, 0, g.n)
      AND r.localcode_ltree < subpath(p.wscode_ltree, 0, g.n + 1)
      ORDER BY r.localcode_ltree DESC
      LIMIT 1
    ) r
  ) x
  ORDER BY x.levels_up
  LIMIT 1
) a ON m.linear_feature_id IS NULL
  AND p.wscode_ltree IS NOT NULL
  AND NOT p.wscode_ltree <@ '999'::ltree;

ALTER TABLE fwapg.mainflow_tree_area_polygons ADD PRIMARY KEY (watershed_feature_id);
CREATE INDEX ON fwapg.mainflow_tree_area_polygons (linear_feature_id);
ANALYZE fwapg.mainflow_tree_area_polygons;

-- 6. local area, and each segment's depth (steps down to its outlet): the sum
-- runs from the deepest level to the outlets, one level a statement
DROP TABLE IF EXISTS fwapg.mainflow_tree_area;

-- half-full pages, so the sum below updates rows in place
CREATE TABLE fwapg.mainflow_tree_area (
  linear_feature_id bigint PRIMARY KEY,
  downstream_id bigint,
  downstream_method text,          -- node, line, junction; NULL at an outlet
  depth integer,                   -- steps down to the outlet
  local_area_ha double precision,  -- the polygons given to this segment, after sharing
  shared_area_ha double precision, -- of local_area_ha, the length share received (+) or given (-)
  upstream_area_ha double precision
) WITH (fillfactor = 50);

WITH RECURSIVE tree AS (
  SELECT d.linear_feature_id, 0 AS depth
  FROM area_down d
  WHERE d.downstream_id IS NULL
  UNION ALL
  SELECT d.linear_feature_id, t.depth + 1
  FROM area_down d
  INNER JOIN tree t ON d.downstream_id = t.linear_feature_id
),
local AS (
  SELECT linear_feature_id, sum(area_ha) AS area_ha
  FROM fwapg.mainflow_tree_area_polygons
  WHERE linear_feature_id IS NOT NULL
  GROUP BY linear_feature_id
)
INSERT INTO fwapg.mainflow_tree_area
  (linear_feature_id, downstream_id, downstream_method, depth, local_area_ha, upstream_area_ha)
SELECT d.linear_feature_id, d.downstream_id, d.downstream_method, t.depth, coalesce(l.area_ha, 0), coalesce(l.area_ha, 0)
FROM area_down d
LEFT JOIN tree t ON t.linear_feature_id = d.linear_feature_id
LEFT JOIN local l ON l.linear_feature_id = d.linear_feature_id;

CREATE INDEX ON fwapg.mainflow_tree_area (depth);
ANALYZE fwapg.mainflow_tree_area;

-- every segment must be reachable from an outlet, or the steps across a gap
-- have made a cycle and the sum below would leave its segments out
DO $$
DECLARE
  unreached integer;
BEGIN
  SELECT count(*) INTO unreached FROM fwapg.mainflow_tree_area WHERE depth IS NULL;
  IF unreached > 0 THEN
    RAISE EXCEPTION '% tree segments are not reachable from an outlet: the downstream steps have a cycle', unreached;
  END IF;
END $$;

-- a segment's area is its local area plus the finished areas of the segments
-- that flow into it, which are all one level deeper
CREATE FUNCTION pg_temp.mainflow_tree_area_sum() RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  maxdepth integer;
BEGIN
  UPDATE fwapg.mainflow_tree_area SET upstream_area_ha = local_area_ha;
  SELECT max(depth) INTO maxdepth FROM fwapg.mainflow_tree_area;
  FOR d IN REVERSE maxdepth - 1..0 LOOP
    UPDATE fwapg.mainflow_tree_area a
    SET upstream_area_ha = a.local_area_ha + c.area_ha
    FROM (
      SELECT downstream_id, sum(upstream_area_ha) AS area_ha
      FROM fwapg.mainflow_tree_area
      WHERE depth = d + 1
      GROUP BY downstream_id
    ) c
    WHERE a.linear_feature_id = c.downstream_id;
  END LOOP;
END $$;

SELECT pg_temp.mainflow_tree_area_sum();

-- 7. segments with nothing above them: the polygon at their midpoint (the
-- nearest within 500 m where the midpoint is in none), and the length of all
-- tree segments in each such polygon
CREATE TEMPORARY TABLE area_zero AS
SELECT a.linear_feature_id, s.length_metre, coalesce(q.watershed_feature_id, n.watershed_feature_id) AS watershed_feature_id
FROM fwapg.mainflow_tree_area a
INNER JOIN whse_basemapping.fwa_stream_networks_sp s ON s.linear_feature_id = a.linear_feature_id
LEFT JOIN LATERAL (
  SELECT w.watershed_feature_id
  FROM whse_basemapping.fwa_watersheds_poly w
  WHERE ST_Intersects(w.geom, ST_LineInterpolatePoint(s.geom, 0.5))
  ORDER BY w.watershed_feature_id
  LIMIT 1
) q ON true
LEFT JOIN LATERAL (
  SELECT w.watershed_feature_id
  FROM whse_basemapping.fwa_watersheds_poly w
  WHERE ST_DWithin(w.geom, ST_LineInterpolatePoint(s.geom, 0.5), 500)
  ORDER BY ST_Distance(w.geom, ST_LineInterpolatePoint(s.geom, 0.5)), w.watershed_feature_id
  LIMIT 1
) n ON q.watershed_feature_id IS NULL
WHERE a.upstream_area_ha = 0;

CREATE TEMPORARY TABLE area_zero_share AS
WITH other AS (
  -- tree segments in the same polygons that already carry area
  SELECT z.watershed_feature_id, sum(s.length_metre) AS length_metre
  FROM (SELECT DISTINCT watershed_feature_id FROM area_zero WHERE watershed_feature_id IS NOT NULL) z
  INNER JOIN whse_basemapping.fwa_watersheds_poly w ON w.watershed_feature_id = z.watershed_feature_id
  INNER JOIN whse_basemapping.fwa_stream_networks_sp s
    ON ST_Intersects(w.geom, s.geom)
    AND ST_Intersects(w.geom, ST_LineInterpolatePoint(s.geom, 0.5))
  INNER JOIN fwapg.mainflow_tree_area a ON a.linear_feature_id = s.linear_feature_id
  WHERE a.upstream_area_ha > 0
  GROUP BY z.watershed_feature_id
),
total AS (
  SELECT z.watershed_feature_id, sum(z.length_metre) + coalesce(max(o.length_metre), 0) AS length_metre
  FROM area_zero z
  LEFT JOIN other o ON o.watershed_feature_id = z.watershed_feature_id
  WHERE z.watershed_feature_id IS NOT NULL
  GROUP BY z.watershed_feature_id
)
SELECT z.linear_feature_id, z.watershed_feature_id, p.area_ha * z.length_metre / t.length_metre AS share_ha
FROM area_zero z
INNER JOIN total t ON t.watershed_feature_id = z.watershed_feature_id
INNER JOIN fwapg.mainflow_tree_area_polygons p ON p.watershed_feature_id = z.watershed_feature_id;

UPDATE fwapg.mainflow_tree_area a
SET local_area_ha = z.share_ha, shared_area_ha = z.share_ha
FROM area_zero_share z
WHERE a.linear_feature_id = z.linear_feature_id;

-- taken from the segment the polygon was given to; a polygon given to none
-- keeps the rest of its area unassigned
UPDATE fwapg.mainflow_tree_area a
SET local_area_ha = a.local_area_ha - g.share_ha, shared_area_ha = -g.share_ha
FROM (
  SELECT p.linear_feature_id, sum(z.share_ha) AS share_ha
  FROM area_zero_share z
  INNER JOIN fwapg.mainflow_tree_area_polygons p ON p.watershed_feature_id = z.watershed_feature_id
  WHERE p.linear_feature_id IS NOT NULL
  GROUP BY p.linear_feature_id
) g
WHERE a.linear_feature_id = g.linear_feature_id;

UPDATE fwapg.mainflow_tree_area_polygons p
SET shared_ha = g.share_ha
FROM (
  SELECT watershed_feature_id, sum(share_ha) AS share_ha
  FROM area_zero_share
  GROUP BY watershed_feature_id
) g
WHERE p.watershed_feature_id = g.watershed_feature_id;

SELECT pg_temp.mainflow_tree_area_sum();

-- 8. polygons no rule places, by class
DROP TABLE IF EXISTS fwapg.mainflow_tree_area_unassigned;

CREATE TABLE fwapg.mainflow_tree_area_unassigned AS
SELECT
  w.watershed_feature_id,
  w.watershed_group_code,
  w.wscode_ltree,
  w.localcode_ltree,
  p.area_ha,
  p.shared_ha,
  CASE
    WHEN w.wscode_ltree <@ '999'::ltree THEN '999'
    -- its watershed code, and every ancestor of it, is on no tree segment
    WHEN w.wscode_ltree IS NOT NULL THEN 'no stream'
  END AS class
FROM fwapg.mainflow_tree_area_polygons p
INNER JOIN whse_basemapping.fwa_watersheds_poly w ON w.watershed_feature_id = p.watershed_feature_id
WHERE p.linear_feature_id IS NULL;

ALTER TABLE fwapg.mainflow_tree_area_unassigned ADD PRIMARY KEY (watershed_feature_id);

-- 9. the area on the tree (the column is added here for a tree built before it
-- was part of the table)
ALTER TABLE whse_basemapping.fwa_stream_networks_mainflow_tree ADD COLUMN IF NOT EXISTS upstream_area_ha double precision;

UPDATE whse_basemapping.fwa_stream_networks_mainflow_tree t
SET upstream_area_ha = a.upstream_area_ha
FROM fwapg.mainflow_tree_area a
WHERE a.linear_feature_id = t.linear_feature_id;

VACUUM ANALYZE whse_basemapping.fwa_stream_networks_mainflow_tree;
VACUUM ANALYZE fwapg.mainflow_tree_area;
