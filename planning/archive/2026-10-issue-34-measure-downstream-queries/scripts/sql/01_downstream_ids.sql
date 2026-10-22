-- fwapg.downstream_ids (#34): the next segment downstream of every network
-- segment, walked with a recursive CTE (04_walk_pointer.sql).
--
-- Rules, applied in order to every segment, tree or not; null only when none
-- applies:
--
-- 1. node:     the main-flow tree segment whose upstream end is this segment's
--              downstream end. Nodes are segment ends at 1 cm, as mainflow_tree.sql
--              and qa_topology.sql define them. The tree has no splits (asserted
--              below by a primary key), so the target is unique for any source.
-- 2. line:     the next segment down the same blue line (no line has two segments
--              at one downstream_route_measure: 00_env.sql).
-- 3. junction: for the lowest segment of a line with a blue line path: the
--              highest segment of the first line on the path that has one more
--              than 1 mm below the junction. That is the parent (blk_parents) unless
--              the junction is at or below the parent's own lowest segment, when
--              the water passes the parent's mouth and the next line on the path
--              takes it, as the array walk does.
-- 4. null:     outlets at BC's edge, no_parent mouths, lines with no path.
--
-- step_m is the length walked from this segment's downstream end to the
-- downstream end of downstream_id: the target's length_metre after a node or
-- line step; after a junction step, junction_measure - downstream_route_measure
-- of the target (the water enters mid-segment), or its length_metre when the
-- junction is within 1 cm of the target's top. 03_walk_arrays.sql uses the same
-- expression, so the array and pointer walks accumulate the same distances.

\timing on

SELECT clock_timestamp() AS build_t0 \gset

CREATE TEMPORARY TABLE ds_seg AS
SELECT
  s.linear_feature_id,
  s.blue_line_key,
  s.downstream_route_measure AS drm,
  s.length_metre,
  t.linear_feature_id IS NOT NULL AS in_tree,
  round(ST_X(ST_StartPoint(s.geom)) * 100)::bigint AS dn_x,
  round(ST_Y(ST_StartPoint(s.geom)) * 100)::bigint AS dn_y,
  round(ST_X(ST_EndPoint(s.geom)) * 100)::bigint AS up_x,
  round(ST_Y(ST_EndPoint(s.geom)) * 100)::bigint AS up_y
FROM whse_basemapping.fwa_stream_networks_sp s
LEFT JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t
  ON t.linear_feature_id = s.linear_feature_id;

-- 1. tree segments by upstream node; the key fails the build on a split
CREATE TEMPORARY TABLE ds_tree_up AS
SELECT up_x, up_y, linear_feature_id, length_metre
FROM ds_seg
WHERE in_tree;

ALTER TABLE ds_tree_up ADD PRIMARY KEY (up_x, up_y);

-- 2. the next segment down each blue line
CREATE TEMPORARY TABLE ds_line AS
SELECT
  linear_feature_id,
  lag(linear_feature_id) OVER w AS next_id,
  lag(length_metre) OVER w AS next_length
FROM ds_seg
WINDOW w AS (PARTITION BY blue_line_key ORDER BY drm);

ALTER TABLE ds_line ADD PRIMARY KEY (linear_feature_id);

-- 3. the lowest segment of each line with a path: the first line on the path
-- with a segment more than 1 mm below its junction
CREATE TEMPORARY TABLE ds_junction AS
SELECT
  l.linear_feature_id,
  j.linear_feature_id AS target_id,
  CASE
    WHEN j.junction_measure - j.drm >= j.length_metre - 0.01 THEN j.length_metre
    ELSE j.junction_measure - j.drm
  END AS step_m,
  j.step AS path_step
FROM ds_line l
INNER JOIN ds_seg s ON s.linear_feature_id = l.linear_feature_id
INNER JOIN fwapg.blk_paths bp ON bp.blue_line_key = s.blue_line_key
CROSS JOIN LATERAL (
  SELECT t.linear_feature_id, t.drm, t.length_metre, u.measure AS junction_measure, u.step
  FROM unnest(bp.path_blks, bp.path_measures) WITH ORDINALITY AS u(blk, measure, step)
  CROSS JOIN LATERAL (
    SELECT n.linear_feature_id, n.downstream_route_measure AS drm, n.length_metre
    FROM whse_basemapping.fwa_stream_networks_sp n
    WHERE n.blue_line_key = u.blk
    AND n.downstream_route_measure < u.measure - 0.001
    ORDER BY n.downstream_route_measure DESC
    LIMIT 1
  ) t
  ORDER BY u.step
  LIMIT 1
) j
WHERE l.next_id IS NULL;

ALTER TABLE ds_junction ADD PRIMARY KEY (linear_feature_id);

DROP TABLE IF EXISTS fwapg.downstream_ids;

CREATE TABLE fwapg.downstream_ids AS
SELECT
  s.linear_feature_id,
  CASE
    WHEN n.linear_feature_id IS NOT NULL THEN n.linear_feature_id
    WHEN l.next_id IS NOT NULL THEN l.next_id
    ELSE j.target_id
  END AS downstream_id,
  CASE
    WHEN n.linear_feature_id IS NOT NULL THEN n.length_metre
    WHEN l.next_id IS NOT NULL THEN l.next_length
    ELSE j.step_m
  END AS step_m,
  CASE
    WHEN n.linear_feature_id IS NOT NULL THEN 'node'
    WHEN l.next_id IS NOT NULL THEN 'line'
    WHEN j.target_id IS NOT NULL THEN 'junction'
  END AS method,
  s.in_tree
FROM ds_seg s
INNER JOIN ds_line l ON l.linear_feature_id = s.linear_feature_id
LEFT JOIN ds_tree_up n
  ON n.up_x = s.dn_x AND n.up_y = s.dn_y
  AND n.linear_feature_id != s.linear_feature_id
LEFT JOIN ds_junction j ON j.linear_feature_id = s.linear_feature_id;

ALTER TABLE fwapg.downstream_ids ADD PRIMARY KEY (linear_feature_id);
ANALYZE fwapg.downstream_ids;

\timing off

SELECT 'build wall', round(extract(epoch FROM clock_timestamp() - :'build_t0'::timestamptz)::numeric, 1) || ' s';

-- the size the walk uses: the table and its primary key
SELECT 'size fwapg.downstream_ids',
  format('%s rows, heap %s MB, primary key %s MB, total %s MB',
    (SELECT count(*) FROM fwapg.downstream_ids),
    round(pg_relation_size('fwapg.downstream_ids') / 1048576.0),
    round(pg_relation_size('fwapg.downstream_ids_pkey') / 1048576.0),
    round(pg_total_relation_size('fwapg.downstream_ids') / 1048576.0));

SELECT 'junction steps past the parent (path step > 1)', count(*)
FROM ds_junction
WHERE path_step > 1;

-- kept for the QA and the comparison: which lines' lowest segment took which step
DROP TABLE IF EXISTS fwapg.bench_junction_steps;
CREATE TABLE fwapg.bench_junction_steps AS SELECT * FROM ds_junction;
