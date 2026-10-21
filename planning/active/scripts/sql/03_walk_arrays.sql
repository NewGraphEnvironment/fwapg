-- Array walks (#34) over fwapg.blk_paths, included with psql variables method
-- (A-pred or A), walk (full or 1km), grp, lo, hi and the sink below. The walk
-- must stay the file's last statement: a cell reads :ERROR after it.
--
-- A-pred: the shipped predicate fwapg.blk_on_or_upstream(a, b) (b on or upstream
--   of a) as a join against fwa_stream_networks_sp, ids only: #30's question of
--   whether the fwa_ functions could use it.
-- A: the walk. Line 0 is the origin's own blue line, at or below the origin; line
--   i (i >= 1) is the i-th line on the origin line's path, below the point where
--   the water joins it (more than 1 mm below the junction measure: water joining
--   at a segment's start does not pass that segment). Each line is one index range
--   on (blue_line_key, downstream_route_measure) below an exclusive upper bound:
--   the origin's measure on line 0 (the origin is a midpoint, so its segment
--   starts below it), junction - 1 mm after. ord is the position on the
--   chain; cum_m the distance from the origin to each segment's downstream end,
--   summed from step_m as 01_downstream_ids.sql defines it: the origin's partial
--   segment, length_metre down a line, and junction - downstream_route_measure
--   (length_metre within 1 cm of the top) on entering a line.
--
--   The 1 km walk bounds each line before reading it: the water enters line 0 at
--   the origin and line i + 1 at junction i, having walked (junction - bottom) of
--   each line before it, a line's bottom being its lowest downstream_route_measure
--   (1,099 lines do not start at 0). A line entered 1,001 m or more from the
--   origin is not read; on the others only the segments from the one holding
--   the point 1 m past the bound up to the junction. The exact cut is then on
--   cum_m, as the pointer walk makes it: a segment is kept when it starts within
--   1,000 m (cum_m - step_m < 1000).

-- How the rows are consumed: the walk's SELECT, which returns (origin_id,
-- linear_feature_id, ord, cum_m), is wrapped in :sink_open ... :sink_close and
-- ended with \gset when :sink_gset is true, ; otherwise.
--   timing cell (bench.sh): one row of aggregates over every column, so every
--     row is computed and none is written (PostgreSQL never runs a data-modifying
--     statement in parallel, and writing new pages is slow on this host mount);
--     :n is the row count.
--   results (07_results.sql, 07_compare.sql): INSERT INTO :out, the default.
-- :explain prefixes the statement with EXPLAIN (05_explain.sql).
\if :{?explain}
\else
\set explain ''
\endif
\if :{?sink_open}
\else
\set sink_open 'INSERT INTO ' :out ' (origin_id, linear_feature_id, ord, cum_m)'
\set sink_close ''
\set sink_gset false
\endif

SELECT :'method' = 'A-pred' AS is_pred, :'walk' = '1km' AS is_1km \gset

\if :is_pred
:explain :sink_open
SELECT o.origin_id, s.linear_feature_id, NULL::integer AS ord, NULL::double precision AS cum_m
FROM fwapg.bench_origins o
INNER JOIN whse_basemapping.fwa_stream_networks_sp s
  ON fwapg.blk_on_or_upstream(s.blue_line_key, s.downstream_route_measure, o.blue_line_key, o.measure)
WHERE o.grp = :'grp' AND o.rnk BETWEEN :lo AND :hi
:sink_close
\if :sink_gset
\gset
\else
;
\endif
\elif :is_1km
:explain :sink_open
WITH lines AS (
  SELECT o.origin_id, o.linear_feature_id AS origin_segment, o.measure AS origin_measure,
    0::bigint AS step, o.blue_line_key AS blk, o.measure AS junction, o.measure AS upper
  FROM fwapg.bench_origins o
  WHERE o.grp = :'grp' AND o.rnk BETWEEN :lo AND :hi
  UNION ALL
  SELECT o.origin_id, o.linear_feature_id, o.measure, u.step, u.blk, u.measure, u.measure - 0.001
  FROM fwapg.bench_origins o
  INNER JOIN fwapg.blk_paths p ON p.blue_line_key = o.blue_line_key
  CROSS JOIN LATERAL unnest(p.path_blks, p.path_measures) WITH ORDINALITY AS u(blk, measure, step)
  WHERE o.grp = :'grp' AND o.rnk BETWEEN :lo AND :hi
),
entered AS (
  SELECT l.*,
    coalesce(sum(l.junction - b.bottom) OVER (
      PARTITION BY l.origin_id ORDER BY l.step
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ), 0) AS entry_m
  FROM lines l
  CROSS JOIN LATERAL (
    SELECT min(s.downstream_route_measure) AS bottom
    FROM whse_basemapping.fwa_stream_networks_sp s
    WHERE s.blue_line_key = l.blk
  ) b
),
bounded AS (
  SELECT e.*,
    coalesce((
      SELECT max(s.downstream_route_measure)
      FROM whse_basemapping.fwa_stream_networks_sp s
      WHERE s.blue_line_key = e.blk
      AND s.downstream_route_measure <= e.junction - (1000 - e.entry_m) - 1
    ), '-infinity') AS lower_drm
  FROM entered e
  WHERE e.entry_m < 1001
),
segs AS (
  SELECT
    b.origin_id,
    b.step,
    s.linear_feature_id,
    s.downstream_route_measure AS drm,
    CASE
      WHEN b.step = 0 AND s.linear_feature_id = b.origin_segment THEN b.origin_measure - s.downstream_route_measure
      WHEN b.step = 0 THEN s.length_metre
      WHEN b.junction - s.downstream_route_measure >= s.length_metre - 0.01 THEN s.length_metre
      ELSE b.junction - s.downstream_route_measure
    END AS step_m
  FROM bounded b
  INNER JOIN whse_basemapping.fwa_stream_networks_sp s
    ON s.blue_line_key = b.blk
    AND s.downstream_route_measure >= b.lower_drm
    AND s.downstream_route_measure < b.upper
),
chain AS (
  SELECT origin_id, linear_feature_id, step_m,
    row_number() OVER w AS ord,
    sum(step_m) OVER w AS cum_m
  FROM segs
  WINDOW w AS (PARTITION BY origin_id ORDER BY step, drm DESC ROWS UNBOUNDED PRECEDING)
)
SELECT origin_id, linear_feature_id, ord::integer AS ord, cum_m
FROM chain
WHERE cum_m - step_m < 1000
:sink_close
\if :sink_gset
\gset
\else
;
\endif
\else
:explain :sink_open
WITH lines AS (
  SELECT o.origin_id, o.linear_feature_id AS origin_segment, o.measure AS origin_measure,
    0::bigint AS step, o.blue_line_key AS blk, o.measure AS junction, o.measure AS upper
  FROM fwapg.bench_origins o
  WHERE o.grp = :'grp' AND o.rnk BETWEEN :lo AND :hi
  UNION ALL
  SELECT o.origin_id, o.linear_feature_id, o.measure, u.step, u.blk, u.measure, u.measure - 0.001
  FROM fwapg.bench_origins o
  INNER JOIN fwapg.blk_paths p ON p.blue_line_key = o.blue_line_key
  CROSS JOIN LATERAL unnest(p.path_blks, p.path_measures) WITH ORDINALITY AS u(blk, measure, step)
  WHERE o.grp = :'grp' AND o.rnk BETWEEN :lo AND :hi
),
segs AS (
  SELECT
    l.origin_id,
    l.step,
    s.linear_feature_id,
    s.downstream_route_measure AS drm,
    CASE
      WHEN l.step = 0 AND s.linear_feature_id = l.origin_segment THEN l.origin_measure - s.downstream_route_measure
      WHEN l.step = 0 THEN s.length_metre
      WHEN l.junction - s.downstream_route_measure >= s.length_metre - 0.01 THEN s.length_metre
      ELSE l.junction - s.downstream_route_measure
    END AS step_m
  FROM lines l
  INNER JOIN whse_basemapping.fwa_stream_networks_sp s
    ON s.blue_line_key = l.blk
    AND s.downstream_route_measure < l.upper
)
SELECT origin_id, linear_feature_id,
  (row_number() OVER w)::integer AS ord,
  sum(step_m) OVER w AS cum_m
FROM segs
WINDOW w AS (PARTITION BY origin_id ORDER BY step, drm DESC ROWS UNBOUNDED PRECEDING)
:sink_close
\if :sink_gset
\gset
\else
;
\endif
\endif
