-- QA tests for the PCIC crosswalk, all should return result = t. Run before the
-- staging tables are dropped; pcic_crosswalk.sh stops before export if any is f.
-- Reports are in qa_report.sql.

-- the segment an outlet is placed on carries the outlet's accumulated flow. Where
-- several outlets share a segment it belongs to the uppermost (as in
-- pcic_crosswalk07_segments.sql), so only that one is checked
WITH placed AS (
  SELECT DISTINCT ON (x.linear_feature_id) x.subid, x.linear_feature_id
  FROM whse_basemapping.pcic_fwa_crosswalk x
  WHERE x.flag IS NULL
  ORDER BY x.linear_feature_id, x.downstream_route_measure DESC, x.depth DESC, x.subid DESC
)
SELECT 'outlet segments carry accumulated flow' AS test,
  bool_and(abs(d.q_m3s - greatest(m.q_acc, 0)) <= 0.001) AS result
FROM placed p
INNER JOIN fwapg.pcic_subbasins_monthly m ON m.subid = p.subid
INNER JOIN whse_basemapping.fwa_stream_networks_discharge_monthly d
  ON d.linear_feature_id = p.linear_feature_id AND d.month = m.month;

-- flow accumulated on the FWA matches PCIC's outflow (mean annual, within 5%) at
-- most placed outlets, and at nearly all large ones. Where it does not, PCIC's
-- network and the FWA join streams in different places.
WITH annual AS (
  SELECT m.subid, avg(m.q_acc) AS q_acc, avg(q.q_m3s) AS q_pcic
  FROM fwapg.pcic_subbasins_monthly m
  INNER JOIN fwapg.pcic_outlet_monthly q ON q.subid = m.subid AND q.month = m.month
  GROUP BY m.subid
)
SELECT 'accumulated flow within 5% of PCIC at >= 90% of placed outlets' AS test,
  avg((abs(q_acc - q_pcic) <= 0.05 * q_pcic + 0.01)::int) >= 0.9 AS result
FROM annual
UNION ALL
SELECT 'accumulated flow within 5% of PCIC at >= 95% of placed outlets over 100 m3/s',
  avg((abs(q_acc - q_pcic) <= 0.05 * q_pcic)::int) >= 0.95
FROM annual
WHERE q_pcic > 100;

-- most outlets with an FWA candidate are placed
SELECT 'placed >= 90% of outlets with a candidate' AS test,
  count(*) FILTER (WHERE flag IS NULL)::numeric / count(*) FILTER (WHERE flag IS DISTINCT FROM 'no_candidate') >= 0.9 AS result
FROM whse_basemapping.pcic_fwa_crosswalk;

-- every output segment has twelve months and no negative flow
SELECT 'twelve months per segment' AS test, bool_and(n = 12) AS result
FROM (SELECT count(*) AS n FROM whse_basemapping.fwa_stream_networks_discharge_monthly GROUP BY linear_feature_id) s;

SELECT 'no negative flow' AS test, NOT EXISTS (
  SELECT 1 FROM whse_basemapping.fwa_stream_networks_discharge_monthly WHERE q_m3s < 0
) AS result;

-- mean annual flow rarely drops by more than 10% from one segment to the next
-- going down any blue line, main stem or side channel (where it is over 10 m3/s).
-- Measured at 10 of 89,251 pairs (0.01%); the ceiling is 0.1%. Misplaced outlets
-- and position comparisons that misread local codes showed as hundreds.
WITH annual AS (
  SELECT s.blue_line_key, s.downstream_route_measure, avg(d.q_m3s) AS q
  FROM whse_basemapping.fwa_stream_networks_sp s
  INNER JOIN whse_basemapping.fwa_stream_networks_discharge_monthly d ON s.linear_feature_id = d.linear_feature_id
  GROUP BY s.blue_line_key, s.downstream_route_measure
),
pairs AS (
  SELECT q, lead(q) OVER (PARTITION BY blue_line_key ORDER BY downstream_route_measure DESC) AS q_down
  FROM annual
)
SELECT 'flow drops > 10% downstream on <= 0.1% of segment pairs over 10 m3/s' AS test,
  count(*) > 0 AND avg((q_down < q * 0.9)::int) <= 0.001 AS result
FROM pairs
WHERE q_down IS NOT NULL
AND q > 10;

-- blue line paths (pcic_crosswalk01_paths.sql): a stream that reaches its parent
-- outside BC has none, and a stream that reaches its parent through a braid does.
-- Projecting mouths onto parents they never touch put the Okanagan on the
-- Columbia in BC; requiring a side channel to touch its own main stem left the
-- Kitsumkalum (which enters the Skeena through a braid) without a path.
SELECT 'the Okanagan, which leaves BC, has no path' AS test,
  EXISTS (SELECT 1 FROM fwapg.pcic_blk_paths)
  AND NOT EXISTS (SELECT 1 FROM fwapg.pcic_blk_paths WHERE blue_line_key = 356570548) AS result;

SELECT 'the Kitsumkalum, which joins the Skeena through a braid, has a path to the Skeena' AS test,
  EXISTS (
    SELECT 1 FROM fwapg.pcic_blk_paths
    WHERE blue_line_key = 360883243 AND 360887278 = ANY(path_blks)
  ) AS result;
