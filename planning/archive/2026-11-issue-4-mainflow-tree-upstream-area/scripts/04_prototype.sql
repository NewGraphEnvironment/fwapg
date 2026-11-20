-- fwapg#4 Phase 1: a prototype of the whole area build, province-wide, in
-- fwapg.proto4_* tables (dropped once the build proper exists), so the classes
-- the plan's rules leave can be counted before the rules are fixed.
--
--   psql $DATABASE_URL -v ON_ERROR_STOP=1 -f 04_prototype.sql

\timing on
SET work_mem = '1GB';
SET max_parallel_workers_per_gather = 4;

-- 1. tree segments with their nodes (1 cm) and codes
DROP TABLE IF EXISTS fwapg.proto4_seg;
CREATE TABLE fwapg.proto4_seg AS
SELECT
  s.linear_feature_id,
  s.blue_line_key,
  s.downstream_route_measure AS drm,
  s.length_metre,
  s.wscode_ltree,
  s.localcode_ltree,
  s.watershed_group_code,
  t.source,
  round(ST_X(ST_StartPoint(s.geom)) * 100)::bigint AS dn_x,
  round(ST_Y(ST_StartPoint(s.geom)) * 100)::bigint AS dn_y,
  round(ST_X(ST_EndPoint(s.geom)) * 100)::bigint AS up_x,
  round(ST_Y(ST_EndPoint(s.geom)) * 100)::bigint AS up_y
FROM whse_basemapping.fwa_stream_networks_sp s
INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t USING (linear_feature_id);

ALTER TABLE fwapg.proto4_seg ADD PRIMARY KEY (linear_feature_id);
-- fails on a split: two tree segments with one upstream node
CREATE UNIQUE INDEX ON fwapg.proto4_seg (up_x, up_y);
CREATE INDEX ON fwapg.proto4_seg (blue_line_key, drm);
ANALYZE fwapg.proto4_seg;

-- 2. downstream pointer. node: the tree segment whose upstream node is this
-- segment's downstream node. Where there is none: the nearest tree segment
-- lower on the same blue line (line), else the first line on the blue line
-- path with a tree segment more than 1 mm below the junction (junction).
DROP TABLE IF EXISTS fwapg.proto4_down;
CREATE TABLE fwapg.proto4_down AS
SELECT
  s.linear_feature_id,
  coalesce(n.linear_feature_id, j.linear_feature_id) AS downstream_id,
  CASE
    WHEN n.linear_feature_id IS NOT NULL THEN 'node'
    WHEN j.step = 0 THEN 'line'
    WHEN j.linear_feature_id IS NOT NULL THEN 'junction'
  END AS method,
  j.step AS path_step
FROM fwapg.proto4_seg s
LEFT JOIN fwapg.proto4_seg n
  ON n.up_x = s.dn_x AND n.up_y = s.dn_y AND n.linear_feature_id != s.linear_feature_id
LEFT JOIN LATERAL (
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
    FROM fwapg.proto4_seg t
    WHERE t.blue_line_key = u.blk
    AND t.drm < u.measure - 0.001
    ORDER BY t.drm DESC
    LIMIT 1
  ) t
  ORDER BY u.step
  LIMIT 1
) j ON n.linear_feature_id IS NULL;

ALTER TABLE fwapg.proto4_down ADD PRIMARY KEY (linear_feature_id);
CREATE INDEX ON fwapg.proto4_down (downstream_id);
ANALYZE fwapg.proto4_down;

-- 3. the top segment of each reach (a watershed code and local code pair) of
-- the tree: main flow before reattached before the rest, then the highest
DROP TABLE IF EXISTS fwapg.proto4_reach;
CREATE TABLE fwapg.proto4_reach AS
SELECT DISTINCT ON (wscode_ltree, localcode_ltree)
  wscode_ltree, localcode_ltree, linear_feature_id, source
FROM fwapg.proto4_seg
WHERE localcode_ltree IS NOT NULL
ORDER BY wscode_ltree, localcode_ltree,
  CASE source WHEN 'mainflow' THEN 1 WHEN 'reattached' THEN 2 ELSE 3 END,
  drm DESC, linear_feature_id;

ALTER TABLE fwapg.proto4_reach ADD PRIMARY KEY (wscode_ltree, localcode_ltree);
ANALYZE fwapg.proto4_reach;

-- 4. each polygon to one segment, by the rule FWA_Upstream gives the lookup:
-- on its own stream, the reach at the greatest local code at or below its own;
-- failing that, on the nearest ancestor code in the tree, the reach at the
-- greatest local code strictly below the code of the branch it lies on
DROP TABLE IF EXISTS fwapg.proto4_poly;
CREATE TABLE fwapg.proto4_poly AS
SELECT
  w.watershed_feature_id,
  ST_Area(w.geom) / 10000 AS area_ha,
  w.wscode_ltree,
  w.localcode_ltree,
  a.linear_feature_id,
  a.levels_up,
  a.localcode_ltree IS NOT DISTINCT FROM w.localcode_ltree AND a.levels_up = 0 AS same_pair,
  a.source
FROM whse_basemapping.fwa_watersheds_poly w
LEFT JOIN LATERAL (
  SELECT x.*
  FROM (
    (SELECT r.linear_feature_id, r.localcode_ltree, r.source, 0 AS levels_up
     FROM fwapg.proto4_reach r
     WHERE r.wscode_ltree = w.wscode_ltree
     AND r.localcode_ltree <= coalesce(w.localcode_ltree, w.wscode_ltree)
     ORDER BY r.localcode_ltree DESC
     LIMIT 1)
    UNION ALL
    SELECT r.linear_feature_id, r.localcode_ltree, r.source, nlevel(w.wscode_ltree) - g.n
    FROM generate_series(nlevel(w.wscode_ltree) - 1, 1, -1) AS g(n)
    CROSS JOIN LATERAL (
      SELECT r.linear_feature_id, r.localcode_ltree, r.source
      FROM fwapg.proto4_reach r
      WHERE r.wscode_ltree = subpath(w.wscode_ltree, 0, g.n)
      AND r.localcode_ltree < subpath(w.wscode_ltree, 0, g.n + 1)
      ORDER BY r.localcode_ltree DESC
      LIMIT 1
    ) r
  ) x
  ORDER BY x.levels_up
  LIMIT 1
) a ON w.wscode_ltree IS NOT NULL AND NOT w.wscode_ltree <@ '999'::ltree;

ALTER TABLE fwapg.proto4_poly ADD PRIMARY KEY (watershed_feature_id);
CREATE INDEX ON fwapg.proto4_poly (linear_feature_id);
ANALYZE fwapg.proto4_poly;

-- 5. local area, depth from the outlets, and the sum from the top down
DROP TABLE IF EXISTS fwapg.proto4_area;
CREATE TABLE fwapg.proto4_area (
  linear_feature_id bigint PRIMARY KEY,
  downstream_id bigint,
  depth integer,
  local_area_ha double precision,
  upstream_area_ha double precision
) WITH (fillfactor = 50);

WITH RECURSIVE tree AS (
  SELECT d.linear_feature_id, 0 AS depth
  FROM fwapg.proto4_down d
  WHERE d.downstream_id IS NULL
  UNION ALL
  SELECT d.linear_feature_id, t.depth + 1
  FROM fwapg.proto4_down d
  INNER JOIN tree t ON d.downstream_id = t.linear_feature_id
),
local AS (
  SELECT linear_feature_id, sum(area_ha) AS area_ha
  FROM fwapg.proto4_poly
  WHERE linear_feature_id IS NOT NULL
  GROUP BY linear_feature_id
)
INSERT INTO fwapg.proto4_area
SELECT d.linear_feature_id, d.downstream_id, t.depth, coalesce(l.area_ha, 0), coalesce(l.area_ha, 0)
FROM fwapg.proto4_down d
LEFT JOIN tree t USING (linear_feature_id)
LEFT JOIN local l USING (linear_feature_id);

CREATE INDEX ON fwapg.proto4_area (depth);
ANALYZE fwapg.proto4_area;

SELECT 'max depth', max(depth), 'unreached (a cycle)', count(*) FILTER (WHERE depth IS NULL) FROM fwapg.proto4_area;

DO $$
DECLARE
  maxdepth integer;
BEGIN
  SELECT max(depth) INTO maxdepth FROM fwapg.proto4_area;
  FOR d IN REVERSE maxdepth - 1..0 LOOP
    UPDATE fwapg.proto4_area a
    SET upstream_area_ha = a.local_area_ha + c.area_ha
    FROM (
      SELECT downstream_id, sum(upstream_area_ha) AS area_ha
      FROM fwapg.proto4_area
      WHERE depth = d + 1
      GROUP BY downstream_id
    ) c
    WHERE a.linear_feature_id = c.downstream_id;
  END LOOP;
END $$;

ANALYZE fwapg.proto4_area;
\timing off
