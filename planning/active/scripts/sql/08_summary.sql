-- Summary of fwapg.bench_timings (#34): one line per cell and settings, as
-- markdown table rows. Run by `bench.sh summary` after the timings.
--
-- A cell's time is the median of its repeats (the warm-up, rep 0, excluded). The
-- single-origin cell times 20 origins three times each: per origin the median of
-- three, then the median and p95 across the 20. ms/origin is the cell's median
-- over its origin count. A cell with no timed repeat (timeout) is projected:
-- L2's random 100,000 from its random 10,000 cell, a whole group from its 1,000
-- subsample, L1's 1,000 from its 100, A-pred's 1,000 from its single origins,
-- each as ms/origin times the origin count. Projected rows: the 1,000 cell's
-- mean rows per origin times the origin count (the group's own 1,000 for a
-- whole group).

CREATE TEMPORARY TABLE cell_n AS
SELECT c.method, c.walk, c.cell, c.per_origin,
  CASE WHEN c.per_origin THEN 1 ELSE (
    SELECT count(*) FROM fwapg.bench_origins o
    WHERE o.grp = c.grp AND o.rnk BETWEEN c.lo AND c.hi
  ) END AS origins,
  c.run_order
FROM fwapg.bench_cells c;

CREATE TEMPORARY TABLE cell_t AS
WITH per_origin AS (
  SELECT method, walk, cell, settings, origin_rank,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY ms) AS ms,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY rows) AS rows
  FROM fwapg.bench_timings
  WHERE rep > 0 AND ms IS NOT NULL AND origin_rank IS NOT NULL
  GROUP BY 1, 2, 3, 4, 5
)
SELECT method, walk, cell, settings,
  count(*) AS reps,
  percentile_cont(0.5) WITHIN GROUP (ORDER BY ms) AS ms,
  percentile_cont(0.95) WITHIN GROUP (ORDER BY ms) AS p95,
  percentile_cont(0.5) WITHIN GROUP (ORDER BY rows) AS rows
FROM per_origin
GROUP BY 1, 2, 3, 4
UNION ALL
SELECT method, walk, cell, settings,
  count(*) FILTER (WHERE ms IS NOT NULL AND rep > 0),
  percentile_cont(0.5) WITHIN GROUP (ORDER BY ms) FILTER (WHERE rep > 0 AND ms IS NOT NULL),
  NULL,
  percentile_cont(0.5) WITHIN GROUP (ORDER BY rows) FILTER (WHERE rep > 0 AND ms IS NOT NULL)
FROM fwapg.bench_timings
WHERE origin_rank IS NULL
GROUP BY 1, 2, 3, 4;

CREATE TEMPORARY TABLE cell_notes AS
SELECT method, walk, cell, settings, string_agg(DISTINCT note, ', ') FILTER (WHERE note != 'warm-up') AS note
FROM fwapg.bench_timings
GROUP BY 1, 2, 3, 4;

-- the cell each one projects from, when it has no timed repeat
CREATE TEMPORARY TABLE cell_base AS
SELECT n.method, n.walk, n.cell,
  CASE
    WHEN n.cell = '100000' THEN '10000'
    WHEN n.cell IN ('ADMS', 'BULK', 'LFRA') THEN n.cell || '_1000'
    WHEN n.method = 'L1' AND n.cell = '1000' THEN '100'
    WHEN n.method = 'A-pred' AND n.cell = '1000' THEN '1'
  END AS from_cell,
  CASE
    WHEN n.cell IN ('ADMS', 'BULK', 'LFRA') THEN n.cell || '_1000'
    ELSE '1000'
  END AS rows_cell
FROM cell_n n;

SELECT format('| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |',
  n.method, n.walk, n.cell, s.settings, n.origins,
  coalesce(round(t.ms::numeric, CASE WHEN t.ms < 100 THEN 2 ELSE 0 END)::text, '—'),
  coalesce(round(t.p95::numeric, 2)::text, ''),
  coalesce(round((t.ms / nullif(n.origins, 0))::numeric, 3)::text,
    'projected ' || round((bt.ms / bn.origins * n.origins / 1000)::numeric, 0) || ' s'),
  coalesce(round(t.rows)::text, '—') || ' / ' ||
    coalesce(round(rt.rows / rn.origins * n.origins)::text, '?'),
  trim(coalesce(cn.note, '') || CASE
    WHEN t.reps IS NULL OR t.reps = 0 THEN ''
    WHEN n.per_origin THEN ' ' || t.reps || ' origins x 3'
    ELSE ' ' || t.reps || ' reps'
  END))
FROM cell_n n
CROSS JOIN (VALUES ('default'), ('noparallel')) AS s(settings)
LEFT JOIN cell_t t ON t.method = n.method AND t.walk = n.walk AND t.cell = n.cell AND t.settings = s.settings AND t.reps > 0
LEFT JOIN cell_notes cn ON cn.method = n.method AND cn.walk = n.walk AND cn.cell = n.cell AND cn.settings = s.settings
LEFT JOIN cell_base b ON b.method = n.method AND b.walk = n.walk AND b.cell = n.cell
LEFT JOIN cell_t bt ON bt.method = n.method AND bt.walk = n.walk AND bt.cell = b.from_cell AND bt.settings = s.settings AND bt.reps > 0
LEFT JOIN cell_n bn ON bn.method = n.method AND bn.walk = n.walk AND bn.cell = b.from_cell
LEFT JOIN cell_t rt ON rt.method = n.method AND rt.walk = n.walk AND rt.cell = b.rows_cell AND rt.settings = 'default' AND rt.reps > 0
LEFT JOIN cell_n rn ON rn.method = n.method AND rn.walk = n.walk AND rn.cell = b.rows_cell
WHERE EXISTS (
  SELECT 1 FROM fwapg.bench_timings x
  WHERE x.method = n.method AND x.walk = n.walk AND x.cell = n.cell AND x.settings = s.settings
)
ORDER BY n.run_order, s.settings;
