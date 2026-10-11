-- The downstream path of every FWA blue line: the chain of (blue line, measure)
-- its water passes through to the sea, starting at its parent.
--
-- Used by extras/pcic_crosswalk (every position comparison) and
-- extras/mainflow_tree (which side channels a main-flow tributary drains through).
-- They replace FWA_Upstream for ordering positions. FWA_Upstream compares local
-- codes, and local codes nest more than one level below their watershed code, run
-- out of order along a blue line, and are compared across main and side channels;
-- each of those put PCIC outlets on the wrong side of a tributary. Here b is on or
-- upstream of a when a's blue line is b's own (at a lower measure) or is on b's
-- path at or below the point where b's water joins it (fwapg.blk_on_or_upstream).
--
-- A line's parent and junction come from, in order:
--
-- 1. (main stems) the lowest segment of the main stem of its parent watershed
--    code whose local code equals its watershed code: an equality, which
--    out-of-order codes do not disturb. Deferred to 3 when the mouth touches a
--    side channel of that main stem: the water then enters the main stem where
--    the side channel rejoins it, not at the code junction (Birkenhead River on
--    the Lillooet: 2 km and 18 m3/s apart).
-- 2. the line its mouth touches (within 1 m) that is further down by watershed
--    code, or a side channel's own main stem (watershed_key).
-- 3. in rounds, until no line is added: the line its mouth touches that already
--    has a parent, further down by watershed code or (for a side channel only) at
--    its own code. Braids rejoin their main stem through sibling braids; without
--    this, 17,200 side channels (and the Kitsumkalum, which enters the Skeena
--    through one) had no path.
-- 4. when the rounds stop adding lines: the deferred code junctions of 1, for main
--    stems still without a parent; then rounds again.
-- 5. then, for side channels still without a parent: their own main stem, at the
--    lowest main-stem segment whose local code equals the side channel's lowest
--    one, or else the main stem's nearest point within 1 km of the mouth (the
--    Seton River side channel that Cayoosh Creek drains through ends 619 m from
--    the Seton and touches nothing); then rounds again.
-- 6. otherwise nowhere: the line has no path. These are lines whose water leaves
--    BC before it reaches its parent (the Okanagan, Kettle and Similkameen reach
--    the Columbia in the US; the Smoky, Tatshenshini and others), lines with no
--    parent code in BC, and their side channels. Projecting mouths onto the
--    nearest point of a parent they never reach put 160 m3/s of US-routed flow
--    on the Columbia in BC.
--
-- The parents cannot form a cycle. Every edge goes to a line at the same
-- watershed code or further down. Main stems always leave their code (edges from
-- 1, 2, 3 and 4 go to a lower code). A same-code edge comes only from a side
-- channel: to its own main stem (2, 5), which then leaves the code, or in a round
-- of 3 to a line that had a parent in an earlier round. So a cycle could only be
-- made of round edges between side channels, and each of those points back in
-- time. Among touched lines the expected parent is preferred, then the deepest
-- code, then the nearest.
--
-- junction_gap_m is the distance from the line's mouth to the junction.
-- Watershed codes under 999 (not on the network) have no path.

CREATE TEMPORARY TABLE blk_lines AS
WITH blks AS (
  SELECT DISTINCT ON (blue_line_key)
    blue_line_key,
    watershed_key,
    wscode_ltree,
    localcode_ltree,
    -- FWA streams are digitized from their downstream end (measure 0)
    ST_StartPoint(ST_GeometryN(geom, 1)) AS mouth
  FROM whse_basemapping.fwa_stream_networks_sp
  WHERE wscode_ltree IS NOT NULL
  AND NOT wscode_ltree <@ '999'
  AND edge_type != 6010
  ORDER BY blue_line_key, downstream_route_measure
),
-- the main blue line of each watershed code
mains AS (
  SELECT DISTINCT ON (wscode_ltree) wscode_ltree, blue_line_key
  FROM blks
  WHERE blue_line_key = watershed_key
  ORDER BY wscode_ltree, blue_line_key
)
SELECT
  b.blue_line_key,
  b.watershed_key,
  b.mouth,
  b.wscode_ltree,
  b.localcode_ltree,
  b.blue_line_key = b.watershed_key AS is_main,
  CASE
    WHEN b.blue_line_key != b.watershed_key THEN b.watershed_key
    ELSE m.blue_line_key
  END AS expected_parent
FROM blks b
LEFT JOIN mains m
  ON b.blue_line_key = b.watershed_key
  AND nlevel(b.wscode_ltree) > 1
  AND m.wscode_ltree = subpath(b.wscode_ltree, 0, nlevel(b.wscode_ltree) - 1);

ALTER TABLE blk_lines ADD PRIMARY KEY (blue_line_key);

-- every line each mouth touches (within 1 m) at its own watershed code or further down
CREATE TEMPORARY TABLE blk_touches AS
SELECT
  b.blue_line_key,
  t.blue_line_key AS touched,
  t.wscode_ltree = b.wscode_ltree AS same_code,
  t.watershed_key AS touched_watershed_key,
  t.blue_line_key = b.expected_parent AS is_expected,
  nlevel(t.wscode_ltree) AS touched_depth,
  t.junction_measure,
  t.gap
FROM blk_lines b
CROSS JOIN LATERAL (
  SELECT DISTINCT ON (s.blue_line_key)
    s.blue_line_key,
    s.watershed_key,
    s.wscode_ltree,
    s.downstream_route_measure + ST_LineLocatePoint(ST_LineMerge(s.geom), b.mouth) * s.length_metre AS junction_measure,
    ST_Distance(s.geom, b.mouth) AS gap
  FROM whse_basemapping.fwa_stream_networks_sp s
  WHERE ST_DWithin(s.geom, b.mouth, 1)
  AND s.blue_line_key != b.blue_line_key
  AND s.edge_type != 6010
  AND s.wscode_ltree @> b.wscode_ltree
  ORDER BY s.blue_line_key, ST_Distance(s.geom, b.mouth)
) t;

CREATE INDEX ON blk_touches (blue_line_key);
CREATE INDEX ON blk_touches (touched);

-- 1. code junctions, unless the mouth touches a side channel of the parent main stem
CREATE TEMPORARY TABLE blk_code_junctions AS
SELECT
  b.blue_line_key,
  b.expected_parent AS parent_blue_line_key,
  j.downstream_route_measure AS junction_measure,
  ST_Distance(j.geom, b.mouth) AS junction_gap_m,
  EXISTS (
    SELECT 1 FROM blk_touches t
    WHERE t.blue_line_key = b.blue_line_key
    AND t.touched_watershed_key = b.expected_parent
    AND t.touched != b.expected_parent
  ) AS deferred
FROM blk_lines b
CROSS JOIN LATERAL (
  SELECT s.downstream_route_measure, s.geom
  FROM whse_basemapping.fwa_stream_networks_sp s
  WHERE s.blue_line_key = b.expected_parent
  AND s.localcode_ltree = b.wscode_ltree
  ORDER BY s.downstream_route_measure
  LIMIT 1
) j
WHERE b.is_main
AND b.expected_parent != b.blue_line_key;

-- 5. a side channel's junction on its own main stem, for side channels the other
-- steps leave without a parent
CREATE TEMPORARY TABLE blk_side_fallback AS
SELECT
  b.blue_line_key,
  b.watershed_key AS parent_blue_line_key,
  coalesce(c.junction_measure, g.junction_measure) AS junction_measure,
  coalesce(c.gap, g.gap) AS junction_gap_m
FROM blk_lines b
LEFT JOIN LATERAL (
  SELECT s.downstream_route_measure AS junction_measure, ST_Distance(s.geom, b.mouth) AS gap
  FROM whse_basemapping.fwa_stream_networks_sp s
  WHERE s.blue_line_key = b.watershed_key
  AND s.localcode_ltree = b.localcode_ltree
  ORDER BY s.downstream_route_measure
  LIMIT 1
) c ON true
LEFT JOIN LATERAL (
  SELECT
    s.downstream_route_measure + ST_LineLocatePoint(ST_LineMerge(s.geom), b.mouth) * s.length_metre AS junction_measure,
    ST_Distance(s.geom, b.mouth) AS gap
  FROM whse_basemapping.fwa_stream_networks_sp s
  WHERE s.blue_line_key = b.watershed_key
  AND ST_DWithin(s.geom, b.mouth, 1000)
  ORDER BY ST_Distance(s.geom, b.mouth)
  LIMIT 1
) g ON true
WHERE NOT b.is_main
AND coalesce(c.junction_measure, g.junction_measure) IS NOT NULL;

DROP TABLE IF EXISTS fwapg.blk_parents;

CREATE TABLE fwapg.blk_parents (
  blue_line_key integer PRIMARY KEY,
  parent_blue_line_key integer,
  junction_measure double precision,
  junction_gap_m double precision,
  junction_method text,          -- code, touch, touch_round, code_deferred, side_fallback
  round integer
);

INSERT INTO fwapg.blk_parents
SELECT blue_line_key, parent_blue_line_key, junction_measure, junction_gap_m, 'code', 0
FROM blk_code_junctions
WHERE NOT deferred;

-- 2. touching a line further down by code, or a side channel's own main stem
INSERT INTO fwapg.blk_parents
SELECT DISTINCT ON (t.blue_line_key)
  t.blue_line_key, t.touched, t.junction_measure, t.gap, 'touch', 0
FROM blk_touches t
INNER JOIN blk_lines b ON b.blue_line_key = t.blue_line_key
WHERE (NOT t.same_code OR (NOT b.is_main AND t.touched = b.watershed_key))
AND NOT EXISTS (SELECT 1 FROM blk_code_junctions c WHERE c.blue_line_key = t.blue_line_key)
ORDER BY t.blue_line_key, t.is_expected DESC, t.touched_depth DESC, t.gap;

-- 3, 4 and 5. rounds of touching a line that already has a parent; when they stop,
-- the deferred code junctions, then rounds again; when they stop again, the side
-- channel fallback, then rounds again
DO $$
DECLARE
  r integer := 0;
  n integer;
  stage integer := 0;
BEGIN
  LOOP
    r := r + 1;
    INSERT INTO fwapg.blk_parents
    SELECT DISTINCT ON (t.blue_line_key)
      t.blue_line_key, t.touched, t.junction_measure, t.gap, 'touch_round', r
    FROM blk_touches t
    INNER JOIN blk_lines b ON b.blue_line_key = t.blue_line_key
    INNER JOIN fwapg.blk_parents p ON p.blue_line_key = t.touched AND p.round < r
    WHERE NOT EXISTS (SELECT 1 FROM fwapg.blk_parents q WHERE q.blue_line_key = t.blue_line_key)
    -- main stems leave their code (see the header: this keeps the parents acyclic)
    AND (NOT t.same_code OR NOT b.is_main)
    ORDER BY t.blue_line_key, t.is_expected DESC, t.touched_depth DESC, t.gap;
    GET DIAGNOSTICS n = ROW_COUNT;

    IF n = 0 THEN
      stage := stage + 1;
      IF stage = 1 THEN
        INSERT INTO fwapg.blk_parents
        SELECT blue_line_key, parent_blue_line_key, junction_measure, junction_gap_m, 'code_deferred', r
        FROM blk_code_junctions c
        WHERE c.deferred
        AND NOT EXISTS (SELECT 1 FROM fwapg.blk_parents q WHERE q.blue_line_key = c.blue_line_key);
      ELSIF stage = 2 THEN
        INSERT INTO fwapg.blk_parents
        SELECT blue_line_key, parent_blue_line_key, junction_measure, junction_gap_m, 'side_fallback', r
        FROM blk_side_fallback f
        WHERE NOT EXISTS (SELECT 1 FROM fwapg.blk_parents q WHERE q.blue_line_key = f.blue_line_key);
      ELSE
        EXIT;
      END IF;
    END IF;
  END LOOP;
END $$;

ANALYZE fwapg.blk_parents;

-- paths: path_blks[1] is the parent and path_measures[1] the junction on it, and
-- so on to the sea
DROP TABLE IF EXISTS fwapg.blk_paths;

CREATE TABLE fwapg.blk_paths AS
WITH RECURSIVE walk AS (
  SELECT
    blue_line_key,
    ARRAY[parent_blue_line_key] AS path_blks,
    ARRAY[junction_measure] AS path_measures
  FROM fwapg.blk_parents
  UNION ALL
  SELECT
    w.blue_line_key,
    w.path_blks || p.parent_blue_line_key,
    w.path_measures || p.junction_measure
  FROM walk w
  INNER JOIN fwapg.blk_parents p ON p.blue_line_key = w.path_blks[cardinality(w.path_blks)]
  -- stop at a revisit; the check below fails the run if one happened
  WHERE NOT p.parent_blue_line_key = ANY(w.path_blks)
  AND p.parent_blue_line_key != w.blue_line_key
)
SELECT DISTINCT ON (blue_line_key) blue_line_key, path_blks, path_measures
FROM walk
ORDER BY blue_line_key, cardinality(path_blks) DESC;

ALTER TABLE fwapg.blk_paths ADD PRIMARY KEY (blue_line_key);
ANALYZE fwapg.blk_paths;

-- a path whose last line has a parent is a path cut short by a cycle
DO $$
DECLARE
  n integer;
BEGIN
  SELECT count(*) INTO n
  FROM fwapg.blk_paths bp
  INNER JOIN fwapg.blk_parents p ON p.blue_line_key = bp.path_blks[cardinality(bp.path_blks)];
  IF n > 0 THEN
    RAISE EXCEPTION '% blue line paths end in a cycle of parent lines', n;
  END IF;
END $$;

-- b (blue line, measure) is on or upstream of a
CREATE OR REPLACE FUNCTION fwapg.blk_on_or_upstream(
  blk_a integer, drm_a double precision,
  blk_b integer, drm_b double precision
) RETURNS boolean
LANGUAGE sql STABLE PARALLEL SAFE AS $$
  SELECT
    (blk_b = blk_a AND drm_b >= drm_a)
    OR EXISTS (
      SELECT 1
      FROM fwapg.blk_paths p,
      unnest(p.path_blks, p.path_measures) AS u(blk, measure)
      WHERE p.blue_line_key = blk_b
      AND u.blk = blk_a
      AND u.measure >= drm_a
    )
$$;
