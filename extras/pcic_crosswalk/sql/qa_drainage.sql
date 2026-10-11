-- Drainage check at every placed outlet.
--
-- Is each placed outlet on a stream of the right size? PCIC publishes no
-- sub-basin areas, so PCIC's drainage size is measured two ways and compared with
-- the FWA upstream area at the segment the outlet is placed on:
--
-- - density: PCIC's upstream river length (the summed length of the PCIC river
--   segments in the outlet's PCIC subtree) per FWA km². PCIC's network has a
--   roughly even density, but a headwater outlet's FWA area includes ground above
--   the tip of PCIC's network, so this reads low on short subtrees, and a subtree
--   of PCIC lakes only has no river length at all (those outlets are judged by
--   runoff alone).
-- - runoff: PCIC's mean annual flow at the outlet per FWA km². Not biased at
--   headwaters (PCIC's flow covers the whole sub-basin), but noisy where runoff
--   varies within a region.
--
-- Each is normalised by its median over the outlet's watershed group (over the
-- province where the group has fewer than 20 main-stem placements). An outlet
-- is flagged only when both agree: 'small' (both < 0.2: a small PCIC outlet on a
-- much bigger FWA stream) or 'big' (both > 5). Neither uses the FWA's accumulated
-- flow, so the check sees what flow agreement cannot: a chain of outlets shifted
-- onto a neighbouring stream still adds up.
--
-- Only outlets placed on a main stem are checked: the watershed lookup gives a
-- side channel its main river's area (217,390 km² for Maria Slough), so area means
-- nothing there. Placed vs nearest-candidate area is reported too, i.e. where
-- placement overrode proximity; on its own it cannot say which was right.
--
-- Measured 2026-10-09: 218 'small' (82 of the 85 outlets carrying > 10 times
-- PCIC's flow among them), 126 'big', of 37,040 main-stem placements. Seeded
-- errors: the Nicola main stem put back on Clapperton Creek is flagged; 200 of 200
-- small outlets moved onto a candidate with 10x the area, and 198 of 200 big ones
-- moved onto a tenth, are flagged. A wrong stream of similar size (within ~5x) is
-- not. Flags are a review list, not each a defect: lake connector lines
-- (1410), double-line river construction lines (1250, 1200) and regulated flow
-- (Cheslatta River, Nechako Reservoir releases) also trip it.
--
-- Builds fwapg.pcic_qa_drainage; run before the staging tables are dropped.

DROP TABLE IF EXISTS fwapg.pcic_qa_drainage;

CREATE TABLE fwapg.pcic_qa_drainage AS
WITH RECURSIVE up AS (
  SELECT subid, subid AS member FROM fwapg.pcic_outlets
  UNION ALL
  SELECT up.subid, o.subid
  FROM up
  INNER JOIN fwapg.pcic_outlets o ON o.dowsubid = up.member
),
pcic_length AS (
  SELECT up.subid, sum(coalesce(ST_Length(r.geom), 0)) / 1000 AS pcic_length_km
  FROM up
  LEFT JOIN fwapg.pcic_rivers r ON r.subid = up.member
  GROUP BY up.subid
),
pcic_flow AS (
  SELECT subid, avg(q_m3s) AS q_m3s FROM fwapg.pcic_outlet_monthly GROUP BY subid
),
area AS (
  SELECT l.linear_feature_id, ua.upstream_area_ha / 100 AS area_km2
  FROM whse_basemapping.fwa_streams_watersheds_lut l
  INNER JOIN whse_basemapping.fwa_watersheds_upstream_area ua ON l.watershed_feature_id = ua.watershed_feature_id
),
placed AS (
  SELECT
    x.subid,
    x.watershed_group_code,
    x.blue_line_key,
    s.edge_type,
    s.blue_line_key = s.watershed_key AS main_stem,
    x.candidate_rank,
    x.distance_to_stream,
    pl.pcic_length_km,
    pf.q_m3s AS pcic_q_m3s,
    a.area_km2 AS fwa_area_km2,
    r1.area_km2 AS nearest_area_km2
  FROM whse_basemapping.pcic_fwa_crosswalk x
  INNER JOIN whse_basemapping.fwa_stream_networks_sp s ON s.linear_feature_id = x.linear_feature_id
  INNER JOIN pcic_length pl ON pl.subid = x.subid
  INNER JOIN pcic_flow pf ON pf.subid = x.subid
  LEFT JOIN area a ON a.linear_feature_id = x.linear_feature_id
  LEFT JOIN fwapg.pcic_candidates c1 ON c1.subid = x.subid AND c1.candidate_rank = 1
  LEFT JOIN area r1 ON r1.linear_feature_id = c1.linear_feature_id
  WHERE x.flag IS NULL
),
-- medians per watershed group, and over the province for groups with fewer than
-- 20 main-stem placements, where one outlet would move the median it is judged by
regional AS (
  SELECT
    watershed_group_code,
    count(*) AS n,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY pcic_length_km / fwa_area_km2) AS median_density,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY pcic_q_m3s / fwa_area_km2) AS median_runoff
  FROM placed
  WHERE main_stem AND fwa_area_km2 > 0
  GROUP BY watershed_group_code
),
province AS (
  SELECT
    percentile_cont(0.5) WITHIN GROUP (ORDER BY pcic_length_km / fwa_area_km2) AS median_density,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY pcic_q_m3s / fwa_area_km2) AS median_runoff
  FROM placed
  WHERE main_stem AND fwa_area_km2 > 0
),
ratios AS (
  SELECT
    p.*,
    (p.pcic_length_km / nullif(p.fwa_area_km2, 0))
      / nullif(CASE WHEN r.n >= 20 THEN r.median_density ELSE pv.median_density END, 0) AS density_ratio,
    (p.pcic_q_m3s / nullif(p.fwa_area_km2, 0))
      / nullif(CASE WHEN r.n >= 20 THEN r.median_runoff ELSE pv.median_runoff END, 0) AS runoff_ratio
  FROM placed p
  CROSS JOIN province pv
  LEFT JOIN regional r ON r.watershed_group_code = p.watershed_group_code
)
SELECT
  subid,
  watershed_group_code,
  blue_line_key,
  edge_type,
  main_stem,
  candidate_rank,
  round(distance_to_stream::numeric, 1) AS distance_to_stream,
  round(pcic_length_km::numeric, 2) AS pcic_length_km,
  round(pcic_q_m3s::numeric, 3) AS pcic_q_m3s,
  round(fwa_area_km2::numeric, 2) AS fwa_area_km2,
  round(nearest_area_km2::numeric, 2) AS nearest_area_km2,
  round(density_ratio::numeric, 3) AS density_ratio,
  round(runoff_ratio::numeric, 3) AS runoff_ratio,
  round((fwa_area_km2 / nullif(nearest_area_km2, 0))::numeric, 3) AS placed_over_nearest_area,
  CASE
    WHEN NOT main_stem THEN NULL
    -- no FWA area (no watershed row, or 0) or no median: not checked, and counted
    -- as such, so a missing table cannot read as "nothing flagged"
    WHEN density_ratio IS NULL OR runoff_ratio IS NULL THEN 'unmeasured'
    -- a subtree of PCIC lakes only has no river length, so density is 0 by
    -- construction, not a measurement: judge it by runoff alone
    WHEN pcic_length_km = 0 AND runoff_ratio < 0.2 THEN 'small'
    WHEN pcic_length_km = 0 AND runoff_ratio > 5 THEN 'big'
    WHEN pcic_length_km = 0 THEN NULL
    WHEN density_ratio < 0.2 AND runoff_ratio < 0.2 THEN 'small'
    WHEN density_ratio > 5 AND runoff_ratio > 5 THEN 'big'
  END AS flag,
  CASE
    WHEN NOT main_stem THEN NULL
    WHEN pcic_length_km = 0 THEN 'runoff only (lakes only upstream in PCIC)'
    ELSE 'density and runoff'
  END AS judged_by
FROM ratios;

ALTER TABLE fwapg.pcic_qa_drainage ADD PRIMARY KEY (subid);
ANALYZE fwapg.pcic_qa_drainage;

-- report
SELECT
  coalesce(flag, CASE WHEN main_stem THEN 'ok' ELSE 'not checked (side channel)' END) AS drainage,
  count(*),
  count(*) FILTER (WHERE judged_by LIKE 'runoff only%') AS runoff_only,
  count(*) FILTER (WHERE candidate_rank > 1) AS not_nearest_candidate,
  count(*) FILTER (WHERE pcic_length_km < 5) AS pcic_subtree_under_5km
FROM fwapg.pcic_qa_drainage
GROUP BY 1
ORDER BY 1;

SELECT flag, edge_type, count(*)
FROM fwapg.pcic_qa_drainage
WHERE flag IN ('small', 'big')
GROUP BY 1, 2
ORDER BY 1, 3 DESC;
