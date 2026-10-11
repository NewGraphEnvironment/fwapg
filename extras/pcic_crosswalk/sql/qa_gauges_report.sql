-- Summary of fwapg.pcic_qa_gauges (qa_gauges.sh).

-- coverage
SELECT
  count(*) AS gauges,
  count(*) FILTER (WHERE q_fwa IS NOT NULL) AS with_fwa_flow,
  count(*) FILTER (WHERE q_pcic IS NOT NULL) AS with_pcic_flow,
  count(*) FILTER (WHERE q_fwa IS NOT NULL AND q_pcic IS NOT NULL) AS compared
FROM fwapg.pcic_qa_gauges;

-- crosswalk: FWA flow against PCIC flow at the same gauge, by gauge area
SELECT
  CASE
    WHEN gauge_area_km2 < 100 THEN '1: < 100 km2'
    WHEN gauge_area_km2 < 1000 THEN '2: 100-1,000 km2'
    WHEN gauge_area_km2 < 10000 THEN '3: 1,000-10,000 km2'
    ELSE '4: > 10,000 km2'
  END AS gauge_area,
  count(*) AS compared,
  count(*) FILTER (WHERE abs(fwa_over_pcic - 1) <= 0.1) AS within_10pct,
  count(*) FILTER (WHERE abs(fwa_over_pcic - 1) > 0.1 AND any_pcic_matches_fwa) AS other_pcic_branch_matches,
  count(*) FILTER (WHERE abs(fwa_over_pcic - 1) > 0.1 AND NOT any_pcic_matches_fwa) AS disagree,
  count(*) FILTER (WHERE abs(fwa_over_pcic - 1) <= 0.25) AS within_25pct,
  count(*) FILTER (WHERE fwa_over_pcic > 2 OR fwa_over_pcic < 0.5) AS off_2x,
  round(percentile_cont(0.5) WITHIN GROUP (ORDER BY fwa_over_pcic)::numeric, 3) AS median_ratio
FROM fwapg.pcic_qa_gauges
WHERE q_fwa IS NOT NULL AND q_pcic IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- stream matching: FWA upstream area against the gauge's drainage area
SELECT
  count(*) FILTER (WHERE abs(fwa_area_over_gauge - 1) <= 0.1) AS area_within_10pct,
  count(*) FILTER (WHERE abs(fwa_area_over_gauge - 1) > 0.1 AND abs(fwa_area_over_gauge - 1) <= 0.5) AS area_10_50pct,
  count(*) FILTER (WHERE abs(fwa_area_over_gauge - 1) > 0.5) AS area_off_50pct
FROM fwapg.pcic_qa_gauges
WHERE fwa_area_over_gauge IS NOT NULL;

-- PCIC model skill: PCIC flow at the nearest PCIC segment against observed (not a
-- crosswalk check)
SELECT
  count(*) AS gauges,
  round(percentile_cont(0.5) WITHIN GROUP (ORDER BY pcic_over_obs)::numeric, 3) AS median_pcic_over_obs,
  count(*) FILTER (WHERE abs(pcic_over_obs - 1) <= 0.25) AS within_25pct
FROM fwapg.pcic_qa_gauges
WHERE q_pcic IS NOT NULL AND q_obs > 0;

-- the gauges where the crosswalk disagrees with every PCIC segment near the gauge
-- (area-matched gauges only)
SELECT station, name, round(gauge_area_km2::numeric) AS gauge_area_km2, fwa_area_km2, fwa_stream, pcic_subid, pcic_snap_m, pcic_crosswalk_flag,
  q_obs, q_pcic, q_fwa, fwa_over_pcic
FROM fwapg.pcic_qa_gauges
WHERE q_fwa IS NOT NULL AND q_pcic IS NOT NULL
AND abs(fwa_area_over_gauge - 1) <= 0.1
AND abs(fwa_over_pcic - 1) > 0.1
AND NOT any_pcic_matches_fwa
ORDER BY abs(ln(greatest(fwa_over_pcic, 0.001))) DESC
LIMIT 40;
