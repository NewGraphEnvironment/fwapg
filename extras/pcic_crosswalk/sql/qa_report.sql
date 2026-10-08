-- Reports on the PCIC crosswalk. Run before the staging tables are dropped.

-- outlets by flag
SELECT coalesce(flag, 'placed') AS flag, islake, count(*)
FROM whse_basemapping.pcic_fwa_crosswalk
GROUP BY 1, 2
ORDER BY 1, 2;

-- snap distance of placed outlets
SELECT
  count(*) AS placed,
  round(percentile_cont(0.5) WITHIN GROUP (ORDER BY distance_to_stream)::numeric, 1) AS p50_m,
  round(percentile_cont(0.9) WITHIN GROUP (ORDER BY distance_to_stream)::numeric, 1) AS p90_m,
  round(percentile_cont(0.99) WITHIN GROUP (ORDER BY distance_to_stream)::numeric, 1) AS p99_m,
  round(max(distance_to_stream)::numeric, 1) AS max_m,
  count(*) FILTER (WHERE candidate_rank > 1) AS not_nearest_candidate
FROM whse_basemapping.pcic_fwa_crosswalk
WHERE flag IS NULL;

-- PCIC segment ends that do not touch the downstream feature
SELECT direction_method, count(*),
  count(*) FILTER (WHERE gap_to_downstream_m > 1) AS gap_gt_1m,
  count(*) FILTER (WHERE gap_to_downstream_m > 100) AS gap_gt_100m
FROM fwapg.pcic_outlets
GROUP BY 1
ORDER BY 1;

-- outlets with no PNWNAmet series, and sub-basin months with negative local flow
-- (routing lost water that month)
SELECT
  (SELECT count(*) FROM fwapg.pcic_outlets o WHERE NOT EXISTS (SELECT 1 FROM fwapg.pcic_outlet_monthly q WHERE q.subid = o.subid)) AS outlets_without_series,
  (SELECT count(*) FROM fwapg.pcic_subbasins_monthly WHERE q_local < 0) AS subbasin_months_losing,
  (SELECT count(*) FROM fwapg.pcic_subbasins_monthly) AS subbasin_months;

-- accumulated flow on the FWA against PCIC's outflow at placed outlets (mean annual)
WITH annual AS (
  SELECT m.subid, avg(m.q_acc) AS q_acc, avg(q.q_m3s) AS q_pcic
  FROM fwapg.pcic_subbasins_monthly m
  INNER JOIN fwapg.pcic_outlet_monthly q ON q.subid = m.subid AND q.month = m.month
  GROUP BY m.subid
)
SELECT
  CASE
    WHEN abs(q_acc - q_pcic) <= 0.05 * q_pcic + 0.01 THEN 'within 5%'
    WHEN q_acc > q_pcic THEN 'FWA higher'
    ELSE 'FWA lower'
  END AS agreement,
  count(*),
  count(*) FILTER (WHERE q_pcic > 100) AS over_100_m3s
FROM annual
GROUP BY 1
ORDER BY 1;

-- coverage by watershed group: share of segments with monthly flow
SELECT
  s.watershed_group_code,
  count(*) AS segments,
  count(d.linear_feature_id) AS with_flow,
  round(count(d.linear_feature_id)::numeric / count(*), 2) AS share
FROM whse_basemapping.fwa_stream_networks_sp s
LEFT JOIN whse_basemapping.fwa_stream_networks_discharge_monthly d
  ON s.linear_feature_id = d.linear_feature_id AND d.month = 1
WHERE s.edge_type != 6010
GROUP BY s.watershed_group_code
HAVING count(d.linear_feature_id) > 0
ORDER BY share, s.watershed_group_code;
