-- Correctness (#34): set, order and distance differences between the methods'
-- rows in fwapg.bench_res (07_results.sql), into fwapg.bench_diffs, each
-- difference attributed to one class by an ordered list of predicates (the
-- first that holds wins). A difference no predicate explains stays
-- 'unattributed', and the run is not done until that class is empty.
--
-- Pairs (a, b): A-P and A-P 1km (array and pointer walks), L2-A (ltree
-- predicate and array walk), L2-P (derived: the L2-A class where A and P agree
-- on the segment, the A-P class where they do not), L1-L2 (the shipped trace and
-- its predicate, random 1..100) and Apred-A (the array predicate and the array
-- walk, random 1..20).
--
-- "Chain lines" are the array walk's: the origin's blue line (step 0, its
-- junction the origin's measure) and each line on its path (step i, its
-- junction the path measure), with the line the water arrives from.

SET statement_timeout = 0;

-- segments any compared method returned, with what the predicates read
CREATE TEMPORARY TABLE cmp_seg AS
SELECT
  s.linear_feature_id,
  s.blue_line_key,
  s.watershed_key,
  s.blue_line_key = s.watershed_key AS is_main,
  s.downstream_route_measure AS drm,
  s.wscode_ltree,
  s.localcode_ltree,
  s.edge_type,
  EXISTS (SELECT 1 FROM whse_basemapping.fwa_streams f WHERE f.linear_feature_id = s.linear_feature_id) AS in_fwa_streams
FROM whse_basemapping.fwa_stream_networks_sp s
WHERE s.linear_feature_id IN (SELECT DISTINCT linear_feature_id FROM fwapg.bench_res);

ALTER TABLE cmp_seg ADD PRIMARY KEY (linear_feature_id);

CREATE TEMPORARY TABLE cmp_lines AS
SELECT o.origin_id, 0::bigint AS step, o.blue_line_key AS blk, o.measure AS junction,
  NULL::integer AS from_blk, NULL::text AS junction_method
FROM fwapg.bench_origins o
WHERE o.origin_id IN (SELECT DISTINCT origin_id FROM fwapg.bench_res)
UNION ALL
SELECT o.origin_id, u.step, u.blk, u.measure,
  coalesce(p.path_blks[u.step - 1], o.blue_line_key),
  bp.junction_method
FROM fwapg.bench_origins o
INNER JOIN fwapg.blk_paths p ON p.blue_line_key = o.blue_line_key
CROSS JOIN LATERAL unnest(p.path_blks, p.path_measures) WITH ORDINALITY AS u(blk, measure, step)
LEFT JOIN fwapg.blk_parents bp ON bp.blue_line_key = coalesce(p.path_blks[u.step - 1], o.blue_line_key)
WHERE o.origin_id IN (SELECT DISTINCT origin_id FROM fwapg.bench_res);

-- each line's watershed code, and the chain's last line: the origin's line or
-- the last on its path, which has no path of its own (the paths stop there)
ALTER TABLE cmp_lines ADD COLUMN wscode ltree, ADD COLUMN is_last boolean;
UPDATE cmp_lines c SET wscode = (
  SELECT s.wscode_ltree FROM whse_basemapping.fwa_stream_networks_sp s
  WHERE s.blue_line_key = c.blk ORDER BY s.downstream_route_measure LIMIT 1
);
UPDATE cmp_lines c SET is_last = c.step = (SELECT max(m.step) FROM cmp_lines m WHERE m.origin_id = c.origin_id);

CREATE INDEX ON cmp_lines (origin_id, blk);
ANALYZE cmp_lines;


DROP TABLE IF EXISTS fwapg.bench_diffs;

CREATE TABLE fwapg.bench_diffs (
  pair text NOT NULL,
  kind text NOT NULL,              -- set, order, distance
  origin_id integer NOT NULL,
  linear_feature_id bigint,
  in_a boolean,
  in_b boolean,
  detail double precision,         -- distance: metres apart
  prev_linear_feature_id bigint,   -- order: the common segment before it in b's order
  class text
);

-- set differences, pair by pair (07_setdiff.sql)
\set ohi 1000
\set groups true

\set pair A-P
\set ma A
\set wa full
\set mb P
\set wb full
\ir 07_setdiff.sql

\set pair 'A-P 1km'
\set wa 1km
\set wb 1km
\ir 07_setdiff.sql

\set pair L2-A
\set ma L2
\set wa full
\set mb A
\set wb full
\ir 07_setdiff.sql

\set pair L2-P
\set mb P
\ir 07_setdiff.sql

\set ohi 100
\set groups false
\set pair L1-L2
\set ma L1
\set mb L2
\ir 07_setdiff.sql

\set ohi 20
\set pair Apred-A
\set ma A-pred
\set mb A
\ir 07_setdiff.sql

CREATE INDEX ON fwapg.bench_diffs (pair, origin_id, linear_feature_id);

-- order: on the segments both return, walk b's order and count the places where
-- a's order goes backwards (0 when the two orders agree)
INSERT INTO fwapg.bench_diffs (pair, kind, origin_id, linear_feature_id, in_a, in_b, prev_linear_feature_id)
SELECT x.pair, 'order', x.origin_id, x.linear_feature_id, true, true, x.prev_id
FROM (
  SELECT p.pair, a.origin_id, a.linear_feature_id, a.ord AS a_ord,
    lag(a.ord) OVER w AS prev_a_ord,
    lag(a.linear_feature_id) OVER w AS prev_id
  FROM (VALUES ('A-P', 'A', 'P'), ('L2-A', 'L2', 'A'), ('L2-P', 'L2', 'P'), ('L1-L2', 'L1', 'L2')) AS p(pair, ma, mb)
  INNER JOIN fwapg.bench_res a ON a.method = p.ma AND a.walk = 'full'
  INNER JOIN fwapg.bench_res b ON b.method = p.mb AND b.walk = 'full'
    AND b.origin_id = a.origin_id AND b.linear_feature_id = a.linear_feature_id
  WINDOW w AS (PARTITION BY p.pair, a.origin_id ORDER BY b.ord)
) x
WHERE x.a_ord < x.prev_a_ord;

-- distance: A and P on the origins where their sets agree, outlet and every
-- segment, 1 cm
INSERT INTO fwapg.bench_diffs (pair, kind, origin_id, linear_feature_id, in_a, in_b, detail)
SELECT 'A-P' || CASE WHEN a.walk = '1km' THEN ' 1km' ELSE '' END, 'distance', a.origin_id, a.linear_feature_id, true, true,
  abs(a.cum_m - b.cum_m)
FROM fwapg.bench_res a
INNER JOIN fwapg.bench_res b ON b.method = 'P' AND b.walk = a.walk
  AND b.origin_id = a.origin_id AND b.linear_feature_id = a.linear_feature_id
WHERE a.method = 'A'
AND abs(a.cum_m - b.cum_m) > 0.01
AND NOT EXISTS (
  SELECT 1 FROM fwapg.bench_diffs d
  WHERE d.pair = 'A-P' || CASE WHEN a.walk = '1km' THEN ' 1km' ELSE '' END
  AND d.kind = 'set' AND d.origin_id = a.origin_id
);

-- a line's local codes are anomalous at a segment when they run out of order
-- with the measure around it (a segment higher on the line with a lower local
-- code, or lower with a higher one), or nest more than one level below the
-- watershed code: #3's shape
CREATE TEMPORARY TABLE cmp_lc_anomaly AS
SELECT c.linear_feature_id
FROM cmp_seg c
WHERE (c.linear_feature_id IN (SELECT linear_feature_id FROM fwapg.bench_diffs)
  OR c.linear_feature_id IN (SELECT prev_linear_feature_id FROM fwapg.bench_diffs))
AND c.localcode_ltree IS NOT NULL
AND (
  nlevel(c.localcode_ltree) > nlevel(c.wscode_ltree) + 1
  OR EXISTS (
    SELECT 1 FROM whse_basemapping.fwa_stream_networks_sp n
    WHERE n.blue_line_key = c.blue_line_key
    AND n.localcode_ltree IS NOT NULL
    AND (
      (n.downstream_route_measure > c.drm AND n.localcode_ltree < c.localcode_ltree)
      OR (n.downstream_route_measure < c.drm AND n.localcode_ltree > c.localcode_ltree)
    )
  )
);

ALTER TABLE cmp_lc_anomaly ADD PRIMARY KEY (linear_feature_id);

-- ---------------------------------------------------------------- A-P classes

-- the paths stop: the chain's last line (the origin's, or the last on its
-- path) has no path of its own, because its water leaves BC before it reaches
-- its parent, or it has no parent; the array walk ends at that line's mouth, the
-- pointer walk goes on wherever the mouth's node leads
UPDATE fwapg.bench_diffs d SET class = 'path_ends'
WHERE d.pair IN ('A-P', 'A-P 1km') AND d.kind = 'set' AND d.class IS NULL
AND d.in_b AND NOT d.in_a
-- the pointer walk passes the array walk's last segment before reaching it:
-- the array walk is a prefix of the pointer walk, cut where the paths stop
AND (
  SELECT r.ord FROM fwapg.bench_res r
  WHERE r.method = 'P' AND r.walk = CASE WHEN d.pair = 'A-P' THEN 'full' ELSE '1km' END
  AND r.origin_id = d.origin_id AND r.linear_feature_id = d.linear_feature_id
) > (
  SELECT p.ord FROM fwapg.bench_res p
  WHERE p.method = 'P' AND p.walk = CASE WHEN d.pair = 'A-P' THEN 'full' ELSE '1km' END
  AND p.origin_id = d.origin_id
  AND p.linear_feature_id = (
    SELECT a.linear_feature_id FROM fwapg.bench_res a
    WHERE a.method = 'A' AND a.walk = CASE WHEN d.pair = 'A-P' THEN 'full' ELSE '1km' END
    AND a.origin_id = d.origin_id
    ORDER BY a.ord DESC LIMIT 1
  )
)
AND NOT EXISTS (
  SELECT 1 FROM fwapg.bench_diffs e
  WHERE e.pair = d.pair AND e.kind = 'set' AND e.origin_id = d.origin_id AND e.in_a
)
AND EXISTS (SELECT 1 FROM cmp_lines c WHERE c.origin_id = d.origin_id AND c.is_last);

-- the code junction is one segment below the node where the tributary's mouth
-- is: the path's junction measure is the start of the parent segment X whose
-- top is the mouth, so the array walk drops X and the pointer walk keeps it
UPDATE fwapg.bench_diffs d SET class = 'code_junction_below_node'
FROM cmp_seg x, cmp_lines c
WHERE d.pair IN ('A-P', 'A-P 1km') AND d.kind = 'set' AND d.class IS NULL
AND d.in_b
AND x.linear_feature_id = d.linear_feature_id
AND c.origin_id = d.origin_id AND c.step > 0 AND c.blk = x.blue_line_key
AND abs(c.junction - x.drm) <= 0.001
AND EXISTS (
  SELECT 1
  FROM fwapg.downstream_ids i
  WHERE i.downstream_id = x.linear_feature_id
  AND i.method = 'node'
  AND i.linear_feature_id = (
    SELECT s.linear_feature_id FROM whse_basemapping.fwa_stream_networks_sp s
    WHERE s.blue_line_key = c.from_blk ORDER BY s.downstream_route_measure LIMIT 1
  )
);

-- the tree and the paths send the water down different lines and rejoin: the
-- origin has a difference on a line the other method never visits, and both
-- walks end at the same segment, so every difference between follows from the
-- choice of line (a walk cut short would end elsewhere)
UPDATE fwapg.bench_diffs d SET class = 'route_differs'
WHERE d.pair = 'A-P' AND d.kind = 'set' AND d.class IS NULL
AND (
  SELECT r.linear_feature_id FROM fwapg.bench_res r
  WHERE r.method = 'A' AND r.walk = 'full' AND r.origin_id = d.origin_id
  ORDER BY r.ord DESC LIMIT 1
) = (
  SELECT r.linear_feature_id FROM fwapg.bench_res r
  WHERE r.method = 'P' AND r.walk = 'full' AND r.origin_id = d.origin_id
  ORDER BY r.ord DESC LIMIT 1
)
AND EXISTS (
  SELECT 1
  FROM fwapg.bench_diffs e
  INNER JOIN cmp_seg x ON x.linear_feature_id = e.linear_feature_id
  WHERE e.pair = d.pair AND e.kind = 'set' AND e.origin_id = d.origin_id
  AND NOT EXISTS (
    SELECT 1
    FROM fwapg.bench_res r
    INNER JOIN cmp_seg y ON y.linear_feature_id = r.linear_feature_id
    WHERE r.origin_id = e.origin_id
    AND r.method = CASE WHEN e.in_a THEN 'P' ELSE 'A' END
    AND r.walk = 'full'
    AND y.blue_line_key = x.blue_line_key
  )
);

-- 1 km: the same difference as in the full walk (the segment, on the same side)
UPDATE fwapg.bench_diffs d SET class = e.class
FROM fwapg.bench_diffs e
WHERE d.pair = 'A-P 1km' AND d.kind = 'set' AND d.class IS NULL
AND e.pair = 'A-P' AND e.kind = 'set' AND e.class IS NOT NULL
AND e.origin_id = d.origin_id AND e.linear_feature_id = d.linear_feature_id
AND e.in_a = d.in_a AND e.in_b = d.in_b;

-- 1 km: a segment both full walks return, inside one walk's 1 km and not the
-- other's, because a full-walk difference within the first 1 km shifted the
-- distances: that difference's class
UPDATE fwapg.bench_diffs d SET class = (
  SELECT e.class FROM fwapg.bench_diffs e
  WHERE e.pair = 'A-P' AND e.kind = 'set' AND e.origin_id = d.origin_id AND e.class IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM fwapg.bench_res r
    WHERE r.walk = '1km' AND r.origin_id = e.origin_id AND r.linear_feature_id = e.linear_feature_id
  )
  ORDER BY e.linear_feature_id LIMIT 1
)
WHERE d.pair = 'A-P 1km' AND d.kind = 'set' AND d.class IS NULL
AND NOT EXISTS (
  SELECT 1 FROM fwapg.bench_diffs e
  WHERE e.pair = 'A-P' AND e.kind = 'set' AND e.origin_id = d.origin_id AND e.linear_feature_id = d.linear_feature_id
);

UPDATE fwapg.bench_diffs d SET class = 'float_accumulation'
WHERE d.pair IN ('A-P', 'A-P 1km') AND d.kind = 'distance' AND d.class IS NULL
AND d.detail <= 0.01;

-- ---------------------------------------------------------------- L2-A classes

-- a segment under 999 or with a null local code: the ltree predicate's code
-- criteria cannot place it
UPDATE fwapg.bench_diffs d SET class = 'code_999'
FROM cmp_seg x
WHERE d.pair = 'L2-A' AND d.kind = 'set' AND d.class IS NULL
AND x.linear_feature_id = d.linear_feature_id
AND (x.localcode_ltree IS NULL OR x.wscode_ltree <@ '999');

-- the paths stop (as above): the array walk ends at the last line's mouth, and
-- the codes go on down that line's code ancestors (codes above its own, or, for a
-- side channel, its own main stem)
UPDATE fwapg.bench_diffs d SET class = 'path_ends'
FROM cmp_seg x, cmp_lines c
WHERE d.pair = 'L2-A' AND d.kind = 'set' AND d.class IS NULL
AND d.in_a
AND x.linear_feature_id = d.linear_feature_id
AND c.origin_id = d.origin_id AND c.is_last
AND c.wscode <@ x.wscode_ltree
AND (
  c.wscode != x.wscode_ltree
  -- or the last line is a side channel and this is its own main stem
  OR (x.is_main AND EXISTS (
    SELECT 1 FROM whse_basemapping.fwa_stream_networks_sp l
    WHERE l.blue_line_key = c.blk AND l.blue_line_key != l.watershed_key
  ))
)
AND NOT EXISTS (SELECT 1 FROM cmp_lines k WHERE k.origin_id = d.origin_id AND k.blk = x.blue_line_key);

-- side channels: a line the water does not pass through, which the codes count
UPDATE fwapg.bench_diffs d SET class = 'side_channel'
FROM cmp_seg x
WHERE d.pair = 'L2-A' AND d.kind = 'set' AND d.class IS NULL
AND d.in_a
AND x.linear_feature_id = d.linear_feature_id
AND NOT x.is_main
AND NOT EXISTS (SELECT 1 FROM cmp_lines c WHERE c.origin_id = d.origin_id AND c.blk = x.blue_line_key);

-- the path passes a code parent by: the segment is on a main line whose code
-- is an ancestor of the origin's, which the chain never enters, while the chain
-- does enter a line further down by code (the water reaches that line by a
-- touch, not through the code parent)
UPDATE fwapg.bench_diffs d SET class = 'code_parent_bypassed'
FROM cmp_seg x, fwapg.bench_origins o
WHERE d.pair = 'L2-A' AND d.kind = 'set' AND d.class IS NULL
AND d.in_a
AND x.linear_feature_id = d.linear_feature_id AND x.is_main
AND o.origin_id = d.origin_id AND o.wscode_ltree <@ x.wscode_ltree
AND NOT EXISTS (SELECT 1 FROM cmp_lines k WHERE k.origin_id = d.origin_id AND k.blk = x.blue_line_key)
AND EXISTS (
  SELECT 1 FROM cmp_lines k
  WHERE k.origin_id = d.origin_id
  AND k.wscode @> x.wscode_ltree AND k.wscode != x.wscode_ltree
);

-- the path takes the water through a side channel (a braid it touches), which
-- the codes do not count as downstream
UPDATE fwapg.bench_diffs d SET class = 'path_through_side_channel'
FROM cmp_seg x, cmp_lines c
WHERE d.pair = 'L2-A' AND d.kind = 'set' AND d.class IS NULL
AND d.in_b
AND x.linear_feature_id = d.linear_feature_id
AND c.origin_id = d.origin_id AND c.blk = x.blue_line_key AND c.step > 0
AND NOT x.is_main;

-- the main stem beside a side channel the water is in: the water reaches the
-- main stem where the side channel rejoins it, the codes count it from where the
-- side channel leaves
UPDATE fwapg.bench_diffs d SET class = 'alongside_side_channel'
FROM cmp_seg x, cmp_lines c, cmp_seg f
WHERE d.pair = 'L2-A' AND d.kind = 'set' AND d.class IS NULL
AND d.in_a
AND x.linear_feature_id = d.linear_feature_id
AND c.origin_id = d.origin_id AND c.blk = x.blue_line_key AND c.step > 0
AND x.drm >= c.junction - 0.001
AND f.linear_feature_id = (
  SELECT s.linear_feature_id FROM whse_basemapping.fwa_stream_networks_sp s
  WHERE s.blue_line_key = c.from_blk ORDER BY s.downstream_route_measure LIMIT 1
)
AND NOT f.is_main;

-- a side channel rejoining its main stem: the main-stem segments below where it
-- rejoins carry the side channel's own local code, and the codes count a
-- segment of the same watershed code as downstream only when its local code is
-- strictly lower
UPDATE fwapg.bench_diffs d SET class = 'side_channel_rejoin'
FROM cmp_seg x, cmp_lines c
WHERE d.pair = 'L2-A' AND d.kind = 'set' AND d.class IS NULL
AND d.in_b
AND x.linear_feature_id = d.linear_feature_id AND x.is_main
AND c.origin_id = d.origin_id AND c.blk = x.blue_line_key AND c.step > 0
AND x.drm < c.junction - 0.001
AND EXISTS (
  SELECT 1 FROM whse_basemapping.fwa_stream_networks_sp f
  WHERE f.blue_line_key = c.from_blk AND f.blue_line_key != f.watershed_key
);

-- local codes out of order with the measures, or nested deeper than one level,
-- at the segment or at the origin (whose local code is then not under its own
-- watershed code, or nests deeper): the code comparison then answers for a
-- different place than the measures
UPDATE fwapg.bench_diffs d SET class = 'localcode_anomaly'
WHERE d.pair = 'L2-A' AND d.kind = 'set' AND d.class IS NULL
AND (
  d.linear_feature_id IN (SELECT linear_feature_id FROM cmp_lc_anomaly)
  OR (
    EXISTS (
      SELECT 1 FROM fwapg.bench_origins o
      WHERE o.origin_id = d.origin_id
      AND (NOT o.localcode_ltree <@ o.wscode_ltree OR nlevel(o.localcode_ltree) > nlevel(o.wscode_ltree) + 1)
    )
    AND EXISTS (
      SELECT 1 FROM cmp_lines c INNER JOIN cmp_seg x ON x.blue_line_key = c.blk
      WHERE c.origin_id = d.origin_id AND x.linear_feature_id = d.linear_feature_id
    )
  )
);

-- ---------------------------------------------------------------- L2-P classes

UPDATE fwapg.bench_diffs d SET class = e.class
FROM fwapg.bench_diffs e
WHERE d.pair = 'L2-P' AND d.kind = 'set' AND d.class IS NULL
AND e.pair = 'L2-A' AND e.kind = 'set'
AND e.origin_id = d.origin_id AND e.linear_feature_id = d.linear_feature_id
AND e.in_a = d.in_a AND e.in_b = d.in_b
-- A agrees with P on this segment
AND NOT EXISTS (
  SELECT 1 FROM fwapg.bench_diffs ap
  WHERE ap.pair = 'A-P' AND ap.kind = 'set'
  AND ap.origin_id = d.origin_id AND ap.linear_feature_id = d.linear_feature_id
);

UPDATE fwapg.bench_diffs d SET class = ap.class
FROM fwapg.bench_diffs ap
WHERE d.pair = 'L2-P' AND d.kind = 'set' AND d.class IS NULL
AND ap.pair = 'A-P' AND ap.kind = 'set'
AND ap.origin_id = d.origin_id AND ap.linear_feature_id = d.linear_feature_id;

-- ---------------------------------------------------------------- L1-L2 classes

-- the shipped trace reads fwa_streams, which has no row for this segment
UPDATE fwapg.bench_diffs d SET class = 'absent_from_fwa_streams'
FROM cmp_seg x
WHERE d.pair = 'L1-L2' AND d.kind = 'set' AND d.class IS NULL
AND d.in_b
AND x.linear_feature_id = d.linear_feature_id AND NOT x.in_fwa_streams;

-- the trace returned nothing for the origin (its segment is absent from
-- fwa_streams or has no upstream-area row, or the origin is within 1 m of the
-- segment's start)
UPDATE fwapg.bench_diffs d SET class = 'origin_dropped'
WHERE d.pair = 'L1-L2' AND d.kind = 'set' AND d.class IS NULL
AND d.in_b
AND NOT EXISTS (SELECT 1 FROM fwapg.bench_res r WHERE r.method = 'L1' AND r.origin_id = d.origin_id);

-- ---------------------------------------------------------------- Apred-A classes

-- the segment that starts at the junction: the shipped predicate compares
-- measures inclusively (u.measure >= drm), so it counts the segment whose start
-- is the junction; the walk does not, as water joining at a segment's start does
-- not pass it
UPDATE fwapg.bench_diffs d SET class = 'junction_at_segment_start'
FROM cmp_seg x
WHERE d.pair = 'Apred-A' AND d.kind = 'set' AND d.class IS NULL
AND d.in_a AND NOT d.in_b
AND x.linear_feature_id = d.linear_feature_id
AND EXISTS (
  SELECT 1 FROM cmp_lines c
  WHERE c.origin_id = d.origin_id AND c.step > 0 AND c.blk = x.blue_line_key
  AND abs(x.drm - c.junction) <= 0.001
);

-- ---------------------------------------------------------------- order classes

-- two lines at the same codes (a side channel and its main stem, or two lines
-- that both start at measure 0): the code order breaks the tie by measure,
-- which across two lines says nothing about flow
UPDATE fwapg.bench_diffs d SET class = 'code_tie_across_lines'
FROM cmp_seg x, cmp_seg p
WHERE d.kind = 'order' AND d.class IS NULL AND d.pair IN ('L2-A', 'L2-P', 'L1-L2')
AND x.linear_feature_id = d.linear_feature_id
AND p.linear_feature_id = d.prev_linear_feature_id
AND x.blue_line_key != p.blue_line_key
AND x.wscode_ltree = p.wscode_ltree
AND x.localcode_ltree = p.localcode_ltree;

-- local codes out of order along one line: the segment is downstream of the
-- one before it on the same blue line, and its local code is greater
UPDATE fwapg.bench_diffs d SET class = 'localcode_anomaly'
FROM cmp_seg x, cmp_seg p
WHERE d.kind = 'order' AND d.class IS NULL AND d.pair IN ('L2-A', 'L2-P')
AND x.linear_feature_id = d.linear_feature_id
AND p.linear_feature_id = d.prev_linear_feature_id
AND x.blue_line_key = p.blue_line_key
AND x.localcode_ltree > p.localcode_ltree;

UPDATE fwapg.bench_diffs d SET class = 'path_through_side_channel'
FROM cmp_seg x, cmp_seg p
WHERE d.kind = 'order' AND d.class IS NULL AND d.pair IN ('L2-A', 'L2-P')
AND x.linear_feature_id = d.linear_feature_id
AND p.linear_feature_id = d.prev_linear_feature_id
AND (NOT x.is_main OR NOT p.is_main);

UPDATE fwapg.bench_diffs SET class = 'unattributed' WHERE class IS NULL;

-- ---------------------------------------------------------------- report

-- how selective the set-level local-code predicate is: the share of all the
-- array walk's segments it flags, against the share of the differences it
-- explains (all of them, once the classes above it have run)
SELECT 'local-code predicate base rate (array walk segments, 1 in 50 sample)',
  format('%s of %s (%s %%)', count(*) FILTER (WHERE a.linear_feature_id IS NOT NULL), count(*),
    round(100.0 * count(*) FILTER (WHERE a.linear_feature_id IS NOT NULL) / count(*), 1))
FROM (
  SELECT DISTINCT r.linear_feature_id
  FROM fwapg.bench_res r
  INNER JOIN cmp_seg c ON c.linear_feature_id = r.linear_feature_id
  WHERE r.method = 'A' AND r.walk = 'full' AND c.localcode_ltree IS NOT NULL
  AND (hashtext(r.linear_feature_id::text) & 1023) < 20
) x
LEFT JOIN LATERAL (
  SELECT c.linear_feature_id
  FROM cmp_seg c
  WHERE c.linear_feature_id = x.linear_feature_id
  AND (
    nlevel(c.localcode_ltree) > nlevel(c.wscode_ltree) + 1
    OR EXISTS (
      SELECT 1 FROM whse_basemapping.fwa_stream_networks_sp n
      WHERE n.blue_line_key = c.blue_line_key
      AND n.localcode_ltree IS NOT NULL
      AND (
        (n.downstream_route_measure > c.drm AND n.localcode_ltree < c.localcode_ltree)
        OR (n.downstream_route_measure < c.drm AND n.localcode_ltree > c.localcode_ltree)
      )
    )
  )
) a ON true;

SELECT 'order differences L2-A as distinct segment pairs', count(*)
FROM (SELECT DISTINCT linear_feature_id, prev_linear_feature_id FROM fwapg.bench_diffs WHERE pair = 'L2-A' AND kind = 'order') x;

SELECT 'diffs ' || pair || ' ' || kind || ' ' || class,
  format('%s segments, %s origins', count(*), count(DISTINCT origin_id))
FROM fwapg.bench_diffs
GROUP BY pair, kind, class
ORDER BY pair, kind, class;

SELECT 'origins compared ' || method || ' ' || walk, count(DISTINCT origin_id)
FROM fwapg.bench_res
GROUP BY method, walk
ORDER BY method, walk;

SELECT 'origins with a difference ' || pair, count(DISTINCT origin_id)
FROM fwapg.bench_diffs
GROUP BY pair
ORDER BY pair;

SELECT 'largest A-P distance difference where the sets agree (m) ' || a.walk, max(abs(a.cum_m - b.cum_m))
FROM fwapg.bench_res a
INNER JOIN fwapg.bench_res b ON b.method = 'P' AND b.walk = a.walk
  AND b.origin_id = a.origin_id AND b.linear_feature_id = a.linear_feature_id
WHERE a.method = 'A'
AND NOT EXISTS (
  SELECT 1 FROM fwapg.bench_diffs d
  WHERE d.pair = 'A-P' || CASE WHEN a.walk = '1km' THEN ' 1km' ELSE '' END
  AND d.kind = 'set' AND d.origin_id = a.origin_id
)
GROUP BY a.walk
ORDER BY a.walk;

SELECT 'side_channel segments on a main line (expected 0)', count(*)
FROM fwapg.bench_diffs d INNER JOIN cmp_seg x ON x.linear_feature_id = d.linear_feature_id
WHERE d.class = 'side_channel' AND x.is_main;

SELECT 'assert: no unattributed difference',
  NOT EXISTS (SELECT 1 FROM fwapg.bench_diffs WHERE class = 'unattributed');

SELECT 'assert: A and P agree on every distance to 1 cm where their sets agree',
  NOT EXISTS (SELECT 1 FROM fwapg.bench_diffs WHERE kind = 'distance' AND detail > 0.01);

-- ---------------------------------------------------------------- Hope fixture

-- docs/03_functions.md: from Hope, the ltree predicate's segments sum to
-- 308.54 km, 161.40 km on main flow (blue_line_key = watershed_key); whole
-- segments, the origin's included
CREATE TEMPORARY TABLE hope_rows (origin_id integer, linear_feature_id bigint, ord integer, cum_m double precision);
CREATE TEMPORARY TABLE hope (method text, linear_feature_id bigint, cum_m double precision);
\set out hope_rows
\set grp hope
\set lo 1
\set hi 1
\set walk full
\set method L1
\ir 02_walk_ltree.sql
INSERT INTO hope SELECT 'L1', linear_feature_id, cum_m FROM hope_rows;
TRUNCATE hope_rows;
\set method L2
\ir 02_walk_ltree.sql
INSERT INTO hope SELECT 'L2', linear_feature_id, cum_m FROM hope_rows;
TRUNCATE hope_rows;
\set method A
\ir 03_walk_arrays.sql
INSERT INTO hope SELECT 'A', linear_feature_id, cum_m FROM hope_rows;
TRUNCATE hope_rows;
\set method P
\ir 04_walk_pointer.sql
INSERT INTO hope SELECT 'P', linear_feature_id, cum_m FROM hope_rows;

SELECT 'hope ' || h.method,
  format('%s segments, %s km whole, %s km main flow, outlet cum_m %s km',
    count(*),
    round(sum(ST_Length(s.geom))::numeric / 1000, 2),
    round((sum(ST_Length(s.geom)) FILTER (WHERE s.blue_line_key = s.watershed_key))::numeric / 1000, 2),
    coalesce(round(max(h.cum_m)::numeric / 1000, 3)::text, '-'))
FROM hope h
INNER JOIN whse_basemapping.fwa_stream_networks_sp s ON s.linear_feature_id = h.linear_feature_id
GROUP BY h.method
ORDER BY h.method;
