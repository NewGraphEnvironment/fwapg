-- The tree's upstream area against the lookup's (fwa_streams_watersheds_lut
-- with fwa_watersheds_upstream_area), every difference with a class, for review
-- and for the tests in qa.sql. Run after mainflow_tree_area.sql.
--
-- The lookup routes area by watershed codes (FWA_Upstream): a polygon or a
-- tributary counts for every segment whose codes put it below. The tree routes
-- it along its own nodes. The two agree unless something upstream is routed
-- differently, so the classes are found from routing, not from the areas:
-- each thing whose place in the tree is not the place its codes give is a
-- marker, counted for every segment it passes on the way down the tree, and for
-- every segment its codes put below it. A segment whose two counts differ has
-- that marker's kind as its class. Kinds:
--
--   outlet        a line whose mouth is an outlet inside BC (a dead end, a
--                 cut-off or a mouth with no parent the paths lead nowhere from)
--   edge          a line whose mouth is an outlet at BC's edge although its
--                 code has a parent stream in the tree
--   gap           a line whose mouth reaches the tree by a step across a gap
--   side channel  a line whose mouth is on a reattached or followed segment
--   other stream  a line whose mouth is on a main-flow segment of another
--                 stream than its code's parent
--   other place   a line whose mouth is on its parent at another place than
--                 its code gives
--   side polygon  a polygon given to a reattached or followed segment
--   share         a length share given to a stream with no polygon of its own
--   bad code      a polygon whose local code is not under its watershed code:
--                 FWA_Upstream leaves it out, the tree places it by its
--                 watershed code
--
-- Before those, by what the segment and its lookup polygon are: reattached or
-- followed (the lookup gives a side channel its river's area), no lookup row,
-- the lookup's polygon on another stream, the lookup's polygon on the segment's
-- stream at another local code. After them, a segment whose local code is out
-- of order with another segment's on its line (the lookup orders a stream by
-- code, the tree by position).

-- tree segments with their area, their codes and what the lookup gives them
CREATE TEMPORARY TABLE qa_seg AS
SELECT
  a.linear_feature_id,
  a.downstream_id,
  a.downstream_method,
  a.depth,
  a.upstream_area_ha,
  t.source,
  t.watershed_group_code,
  s.blue_line_key,
  s.downstream_route_measure AS drm,
  s.edge_type,
  s.wscode_ltree,
  s.localcode_ltree,
  NULL::boolean AS in_order,
  l.watershed_feature_id,
  w.wscode_ltree AS poly_wscode,
  coalesce(w.localcode_ltree, w.wscode_ltree) AS poly_localcode,
  ua.upstream_area_ha AS lookup_area_ha
FROM fwapg.mainflow_tree_area a
INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t ON t.linear_feature_id = a.linear_feature_id
INNER JOIN whse_basemapping.fwa_stream_networks_sp s ON s.linear_feature_id = a.linear_feature_id
LEFT JOIN whse_basemapping.fwa_streams_watersheds_lut l ON l.linear_feature_id = a.linear_feature_id
LEFT JOIN whse_basemapping.fwa_watersheds_poly w ON w.watershed_feature_id = l.watershed_feature_id
LEFT JOIN whse_basemapping.fwa_watersheds_upstream_area ua ON ua.watershed_feature_id = l.watershed_feature_id;

ALTER TABLE qa_seg ADD PRIMARY KEY (linear_feature_id);
CREATE INDEX ON qa_seg (blue_line_key, drm);
ANALYZE qa_seg;

-- main-flow reaches (code pairs): the top segment of each on its line
CREATE TEMPORARY TABLE qa_reach AS
SELECT DISTINCT ON (wscode_ltree, localcode_ltree)
  wscode_ltree, localcode_ltree, linear_feature_id
FROM qa_seg
WHERE source = 'mainflow' AND localcode_ltree IS NOT NULL
ORDER BY wscode_ltree, localcode_ltree, blue_line_key, drm DESC, linear_feature_id;

ALTER TABLE qa_reach ADD PRIMARY KEY (wscode_ltree, localcode_ltree);
ANALYZE qa_reach;

-- a main-flow segment is in order when no segment above it on its line has a
-- lower local code and none below it a higher one: only then are the segments
-- its codes put above it the ones that are above it. Local codes are ranked
-- within the line so the running extremes are of integers.
UPDATE qa_seg s
SET in_order = o.in_order
FROM (
  SELECT linear_feature_id,
    coalesce(min(code_rank) OVER (PARTITION BY blue_line_key ORDER BY drm DESC ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) >= code_rank, true)
    AND coalesce(max(code_rank) OVER (PARTITION BY blue_line_key ORDER BY drm ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) <= code_rank, true) AS in_order
  FROM (
    SELECT linear_feature_id, blue_line_key, drm,
      dense_rank() OVER (PARTITION BY blue_line_key ORDER BY localcode_ltree) AS code_rank
    FROM qa_seg
    WHERE source = 'mainflow' AND localcode_ltree IS NOT NULL
  ) ranked
) o
WHERE o.linear_feature_id = s.linear_feature_id;

-- markers: where each enters the tree (at_id, NULL for an outlet) and the codes
-- that place it. A line's codes are its watershed code; a polygon's are its own.
CREATE TEMPORARY TABLE qa_marker (
  kind integer,
  at_id bigint,
  wscode_ltree ltree,
  localcode_ltree ltree,  -- NULL for a line
  valid boolean DEFAULT true
);

-- lines: the mouth (lowest tree segment) of each main-flow line, where the tree
-- takes it (x) and where its code puts it (e: the top of the reach on its parent
-- code at the greatest local code below its branch)
INSERT INTO qa_marker (kind, at_id, wscode_ltree)
WITH mouth AS (
  SELECT DISTINCT ON (blue_line_key) *
  FROM qa_seg
  WHERE source = 'mainflow'
  ORDER BY blue_line_key, drm
),
placed AS (
  SELECT
    m.wscode_ltree,
    m.downstream_id,
    CASE
      WHEN m.downstream_id IS NULL AND q.linear_feature_id IS NOT NULL THEN 1          -- outlet
      WHEN m.downstream_id IS NULL AND e.linear_feature_id IS NOT NULL THEN 2          -- edge
      WHEN m.downstream_id IS NULL THEN NULL                                           -- a root: no parent by code either
      WHEN m.downstream_method IN ('line', 'junction') THEN 3                          -- gap
      WHEN x.source != 'mainflow' THEN 4                                               -- side channel
      WHEN e.linear_feature_id IS NULL OR x.wscode_ltree != e.wscode_ltree THEN 5      -- other stream
      WHEN x.linear_feature_id != e.linear_feature_id THEN 6                           -- other place
    END AS kind
  FROM mouth m
  LEFT JOIN qa_seg x ON x.linear_feature_id = m.downstream_id
  LEFT JOIN (SELECT DISTINCT linear_feature_id FROM fwapg.mainflow_tree_qa WHERE kind IN ('dead_end', 'cut_off', 'no_parent')) q
    ON q.linear_feature_id = m.linear_feature_id
  LEFT JOIN LATERAL (
    SELECT r.linear_feature_id, r.wscode_ltree
    FROM generate_series(nlevel(m.wscode_ltree) - 1, 1, -1) AS g(n)
    CROSS JOIN LATERAL (
      SELECT r.linear_feature_id, r.wscode_ltree
      FROM qa_reach r
      WHERE r.wscode_ltree = subpath(m.wscode_ltree, 0, g.n)
      AND r.localcode_ltree < subpath(m.wscode_ltree, 0, g.n + 1)
      ORDER BY r.localcode_ltree DESC
      LIMIT 1
    ) r
    ORDER BY g.n DESC
    LIMIT 1
  ) e ON true
)
SELECT kind, downstream_id, wscode_ltree
FROM placed
WHERE kind IS NOT NULL;

-- polygons given to a side channel, and length shares: each enters the tree at
-- its segment
INSERT INTO qa_marker (kind, at_id, wscode_ltree, localcode_ltree)
SELECT 7, p.linear_feature_id, w.wscode_ltree, coalesce(w.localcode_ltree, w.wscode_ltree)
FROM fwapg.mainflow_tree_area_polygons p
INNER JOIN whse_basemapping.fwa_watersheds_poly w ON w.watershed_feature_id = p.watershed_feature_id
WHERE p.method = 'pair_side'
UNION ALL
SELECT 8, z.linear_feature_id, w.wscode_ltree, coalesce(w.localcode_ltree, w.wscode_ltree)
FROM fwapg.mainflow_tree_area_shares z
INNER JOIN whse_basemapping.fwa_watersheds_poly w ON w.watershed_feature_id = z.watershed_feature_id
WHERE w.wscode_ltree IS NOT NULL;

-- polygons with a local code that is not under their watershed code
INSERT INTO qa_marker (kind, at_id, wscode_ltree, localcode_ltree, valid)
SELECT 9, p.linear_feature_id, w.wscode_ltree, w.localcode_ltree, false
FROM fwapg.mainflow_tree_area_polygons p
INNER JOIN whse_basemapping.fwa_watersheds_poly w ON w.watershed_feature_id = p.watershed_feature_id
WHERE p.linear_feature_id IS NOT NULL
AND NOT w.localcode_ltree <@ w.wscode_ltree;

-- the positions a marker's codes put it above, as FWA_Upstream has it: on its
-- own stream at its local code and below (own, polygons only), and on each
-- ancestor of its watershed code below the branch it lies on. A bad local code
-- counts on an ancestor only where it is under that ancestor, and then below
-- the lower of the branch and the local code; and on its own stream it does not
-- count for the mouth reach (at_mouth), where FWA_Upstream asks that the local
-- code be under the reach's.
CREATE TEMPORARY TABLE qa_marker_code AS
SELECT kind, wscode_ltree, localcode_ltree AS pos, true AS own, valid AS at_mouth
FROM qa_marker
WHERE localcode_ltree IS NOT NULL
UNION ALL
SELECT m.kind, subpath(m.wscode_ltree, 0, g.n),
  CASE WHEN m.valid THEN subpath(m.wscode_ltree, 0, g.n + 1)
       ELSE least(subpath(m.wscode_ltree, 0, g.n + 1), m.localcode_ltree) END,
  false, true
FROM qa_marker m
CROSS JOIN LATERAL generate_series(1, nlevel(m.wscode_ltree) - 1) AS g(n)
WHERE m.valid OR m.localcode_ltree <@ subpath(m.wscode_ltree, 0, g.n);

-- a marker counts 10^(6 * (kind - 1)), so one exact number holds every kind's
-- count (a kind has far fewer than a million markers above any segment)

-- along the tree: each marker at the segment where it enters, summed downstream
-- from the deepest level to the outlets
CREATE TEMPORARY TABLE qa_tree_count (
  linear_feature_id bigint PRIMARY KEY,
  downstream_id bigint,
  depth integer,
  markers numeric
) WITH (fillfactor = 50);

INSERT INTO qa_tree_count
SELECT s.linear_feature_id, s.downstream_id, s.depth, coalesce(m.markers, 0)
FROM qa_seg s
LEFT JOIN (
  SELECT at_id, sum(power(10::numeric, 6 * (kind - 1))) AS markers
  FROM qa_marker
  WHERE at_id IS NOT NULL
  GROUP BY at_id
) m ON m.at_id = s.linear_feature_id;

CREATE INDEX ON qa_tree_count (depth);
ANALYZE qa_tree_count;

DO $$
DECLARE
  maxdepth integer;
BEGIN
  SELECT max(depth) INTO maxdepth FROM qa_tree_count;
  FOR d IN REVERSE maxdepth - 1..0 LOOP
    UPDATE qa_tree_count a
    SET markers = a.markers + c.markers
    FROM (
      SELECT downstream_id, sum(markers) AS markers
      FROM qa_tree_count
      WHERE depth = d + 1 AND markers != 0
      GROUP BY downstream_id
    ) c
    WHERE a.linear_feature_id = c.downstream_id;
  END LOOP;
END $$;

-- by codes: the markers at or above a position on a stream (own), and above it
-- on the branches under the stream (not own), each summed from the top down
CREATE TEMPORARY TABLE qa_code_count AS
SELECT
  wscode_ltree,
  pos,
  own,
  sum(sum(power(10::numeric, 6 * (kind - 1)))) OVER (PARTITION BY wscode_ltree, own ORDER BY pos DESC) AS markers,
  sum(coalesce(sum(power(10::numeric, 6 * (kind - 1))) FILTER (WHERE at_mouth), 0))
    OVER (PARTITION BY wscode_ltree, own ORDER BY pos DESC) AS markers_at_mouth
FROM qa_marker_code
GROUP BY wscode_ltree, pos, own;

CREATE INDEX ON qa_code_count (wscode_ltree, own, pos);
ANALYZE qa_code_count;

-- each segment's two counts
CREATE TEMPORARY TABLE qa_counted AS
SELECT
  s.*,
  c.markers AS tree_markers,
  coalesce(CASE WHEN s.localcode_ltree = s.wscode_ltree THEN o.markers_at_mouth ELSE o.markers END, 0)
    + coalesce(b.markers, 0) AS code_markers,
  abs(s.upstream_area_ha - s.lookup_area_ha) > 1e-9 * greatest(s.lookup_area_ha, 1) AS differs
FROM qa_seg s
INNER JOIN qa_tree_count c ON c.linear_feature_id = s.linear_feature_id
LEFT JOIN LATERAL (
  SELECT k.markers, k.markers_at_mouth FROM qa_code_count k
  WHERE k.wscode_ltree = s.wscode_ltree AND k.own AND k.pos >= s.localcode_ltree
  ORDER BY k.pos LIMIT 1
) o ON true
LEFT JOIN LATERAL (
  SELECT k.markers FROM qa_code_count k
  WHERE k.wscode_ltree = s.wscode_ltree AND NOT k.own AND k.pos > s.localcode_ltree
  ORDER BY k.pos LIMIT 1
) b ON true;

-- every tree segment that differs from the lookup, or has no lookup row
DROP TABLE IF EXISTS fwapg.mainflow_tree_area_qa;

CREATE TABLE fwapg.mainflow_tree_area_qa AS
WITH kinds AS (
  SELECT
    c.*,
    (SELECT string_agg(k.name, ', ' ORDER BY k.kind)
     FROM (VALUES (1, 'outlet'), (2, 'edge'), (3, 'gap'), (4, 'side channel'), (5, 'other stream'),
                  (6, 'other place'), (7, 'side polygon'), (8, 'share'), (9, 'bad code')) AS k (kind, name)
     WHERE mod(trunc(c.tree_markers / power(10::numeric, 6 * (k.kind - 1))), 1000000)
        != mod(trunc(c.code_markers / power(10::numeric, 6 * (k.kind - 1))), 1000000)
    ) AS routed_differently
  FROM qa_counted c
  WHERE c.lookup_area_ha IS NULL OR c.differs
)
SELECT
  k.linear_feature_id,
  k.watershed_group_code,
  k.blue_line_key,
  k.drm AS downstream_route_measure,
  k.source,
  k.edge_type,
  k.upstream_area_ha,
  k.lookup_area_ha,
  -- order matters: the first that holds is the class
  CASE
    WHEN k.source != 'mainflow' THEN k.source
    WHEN k.watershed_feature_id IS NULL THEN 'no lookup row'
    WHEN k.poly_wscode != k.wscode_ltree THEN 'lookup polygon on another stream'
    WHEN k.poly_localcode IS DISTINCT FROM k.localcode_ltree THEN 'lookup polygon at another local code'
    WHEN k.routed_differently IS NOT NULL THEN k.routed_differently
    WHEN NOT k.in_order THEN 'local codes out of order'
    -- the segment's own codes: FWA_Upstream then puts above it what is not
    WHEN NOT k.localcode_ltree <@ k.wscode_ltree THEN 'segment local code not under its watershed code'
    WHEN nlevel(k.localcode_ltree) > nlevel(k.wscode_ltree) + 1 THEN 'segment local code more than one level deep'
  END AS class
FROM kinds k;

ALTER TABLE fwapg.mainflow_tree_area_qa ADD PRIMARY KEY (linear_feature_id);

-- what is left: the lookup's stored area against what its own definition gives
-- now (every polygon FWA_Upstream puts above the segment's lookup polygon). Where
-- the tree agrees with the definition, it is the stored row that differs. At
-- most 5,000 segments are recomputed, each a scan of the polygons under a code.
UPDATE fwapg.mainflow_tree_area_qa q
SET class = 'lookup row is not what its definition gives'
FROM (
  SELECT u.linear_feature_id, (
    SELECT sum(ST_Area(b.geom)) / 10000
    FROM whse_basemapping.fwa_watersheds_poly b
    WHERE FWA_Upstream(u.poly_wscode, u.poly_localcode, b.wscode_ltree, b.localcode_ltree)
  ) AS defined_area_ha
  FROM (
    SELECT q.linear_feature_id, s.poly_wscode, s.poly_localcode
    FROM fwapg.mainflow_tree_area_qa q
    INNER JOIN qa_seg s ON s.linear_feature_id = q.linear_feature_id
    WHERE q.class IS NULL
    ORDER BY q.linear_feature_id
    LIMIT 5000
  ) u
) d
WHERE d.linear_feature_id = q.linear_feature_id
AND abs(q.upstream_area_ha - d.defined_area_ha) <= 1e-9 * greatest(d.defined_area_ha, 1);

-- the comparison's own counts, so the tests can show it is able to fail:
-- main-flow segments whose lookup polygon has both their codes and whose local
-- code is in order on its line, by whether anything upstream is routed
-- differently and whether the areas differ
DROP TABLE IF EXISTS fwapg.mainflow_tree_area_qa_counts;

CREATE TABLE fwapg.mainflow_tree_area_qa_counts AS
SELECT
  count(*) AS comparable,
  count(*) FILTER (WHERE tree_markers = code_markers) AS routed_alike,
  count(*) FILTER (WHERE tree_markers = code_markers AND differs) AS routed_alike_and_differ,
  count(*) FILTER (WHERE tree_markers != code_markers) AS routed_differently,
  count(*) FILTER (WHERE tree_markers != code_markers AND differs) AS routed_differently_and_differ
FROM qa_counted
WHERE source = 'mainflow'
AND poly_wscode = wscode_ltree
AND poly_localcode = localcode_ltree
AND lookup_area_ha IS NOT NULL
AND in_order;
