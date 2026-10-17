-- Segment flow clamped at zero, per :step (fwapg.pcic_discharge_:table): rows
-- whose flow before the clamp (q_raw) was negative, where local runoff (an
-- outlet's flow minus that of the outlets above it) was negative over the period.
-- Over shorter periods water still in transit between outlets makes that more
-- likely, mostly on the rising freshet. Mid-network segments are those with
-- placed outlets above them that are not an outlet's own segment, where the
-- clamp hides flow passing through rather than a losing headwater. Float noise
-- around a true zero also counts as below zero, so rows more than 1 L/s below
-- it are counted on their own.
WITH outlet_segments AS (
  SELECT DISTINCT linear_feature_id FROM fwapg.pcic_fwa_crosswalk WHERE flag IS NULL
),
rows AS (
  SELECT
    d.:step,
    d.q_raw < 0 AS clamped,
    d.q_raw < -0.001 AS clamped_1l,
    cardinality(w.upstream_subids) > 0 AND o.linear_feature_id IS NULL AS mid_network
  FROM fwapg.pcic_discharge_:table d
  INNER JOIN fwapg.pcic_segment_weights w ON w.linear_feature_id = d.linear_feature_id
  LEFT JOIN outlet_segments o ON o.linear_feature_id = d.linear_feature_id
)
SELECT
  coalesce(:step::text, 'all') AS period,
  count(*) AS segment_rows,
  count(*) FILTER (WHERE clamped) AS clamped,
  round(100.0 * count(*) FILTER (WHERE clamped) / count(*), 3) AS clamped_pct,
  count(*) FILTER (WHERE clamped_1l) AS clamped_1l,
  count(*) FILTER (WHERE mid_network) AS mid_network_rows,
  count(*) FILTER (WHERE clamped AND mid_network) AS mid_network_clamped,
  round(100.0 * count(*) FILTER (WHERE clamped AND mid_network) / nullif(count(*) FILTER (WHERE mid_network), 0), 3) AS mid_network_clamped_pct,
  count(*) FILTER (WHERE clamped_1l AND mid_network) AS mid_network_clamped_1l
FROM rows
GROUP BY ROLLUP (:step)
ORDER BY GROUPING(:step), :step;
