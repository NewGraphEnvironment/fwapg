-- Reports on the per-year sub-basin days (DAYS=1), after qa_days.sql passes.

-- how close the files' mean over the years comes to the climatology, against
-- qa_days.sql's tolerance (a ratio of 1 would fail)
SELECT
  max(abs(m.q_local - d.q_local)) AS q_local_max_dev,
  max(abs(m.q_local - d.q_local) / (power(2, -23) * m.abs_local + 1e-9)) AS q_local_max_ratio,
  max(abs(m.q_acc - d.q_acc)) AS q_acc_max_dev,
  max(abs(m.q_acc - d.q_acc) / (power(2, -23) * m.abs_acc + 1e-9)) AS q_acc_max_ratio
FROM fwapg.pcic_days_means m
INNER JOIN fwapg.pcic_subbasins_daily d USING (subid, month, day);

-- Mid-network segment-months clamped at zero, per year of the series, from each
-- year's monthly sub-basin flow (fwapg.pcic_subbasins_months), beside the run's
-- climatology. A segment clamps where pcic_crosswalk09_discharge.sql's
-- q = U + share * L is below zero (U the sum of q_acc above, L the sub-basin's
-- q_local). Segments sharing a sub-basin and the outlets above it differ only by
-- share, so each such group is evaluated once per month: the shares, sorted,
-- below (L > 0) or above (L < 0) -U / L are the ones that clamp (width_bucket
-- counts the shares at or below a value). Mid-network as in qa_report_clamped.sql:
-- placed outlets above, and not an outlet's own segment. The climatology's count
-- is computed the same way and by 09 itself (qa_report_clamped.sql's
-- mid_network_clamped), which it should equal.
WITH outlet_segments AS (
  SELECT DISTINCT linear_feature_id FROM fwapg.pcic_fwa_crosswalk WHERE flag IS NULL
),
groups AS (
  SELECT w.subid, w.upstream_subids, array_agg(w.share ORDER BY w.share) AS shares, count(*) AS n
  FROM fwapg.pcic_segment_weights w
  LEFT JOIN outlet_segments o ON o.linear_feature_id = w.linear_feature_id
  WHERE cardinality(w.upstream_subids) > 0 AND o.linear_feature_id IS NULL
  GROUP BY w.subid, w.upstream_subids
),
flows AS (
  SELECT year, subid, month, q_local, q_acc FROM fwapg.pcic_subbasins_months
  UNION ALL
  SELECT NULL, subid, month, q_local, q_acc FROM fwapg.pcic_subbasins_monthly
),
upstream AS (
  SELECT g.subid, g.upstream_subids, f.year, f.month, sum(f.q_acc) AS u
  FROM groups g
  CROSS JOIN LATERAL unnest(g.upstream_subids) AS a(subid)
  INNER JOIN flows f ON f.subid = a.subid
  GROUP BY g.subid, g.upstream_subids, f.year, f.month
),
clamped AS (
  SELECT u.year, u.month,
    sum(CASE
      WHEN f.q_local > 0 THEN width_bucket(-u.u / f.q_local, g.shares)
      WHEN f.q_local < 0 THEN g.n - width_bucket(-u.u / f.q_local, g.shares)
      WHEN u.u < 0 THEN g.n
      ELSE 0
    END) AS n
  FROM upstream u
  INNER JOIN groups g ON g.subid = u.subid AND g.upstream_subids = u.upstream_subids
  INNER JOIN flows f ON f.subid = u.subid AND f.month = u.month AND f.year IS NOT DISTINCT FROM u.year
  GROUP BY u.year, u.month
),
per_year AS (
  SELECT year, sum(n) AS clamped, string_agg(n::text, ' ' ORDER BY month) AS by_month
  FROM clamped
  GROUP BY year
)
SELECT
  coalesce(p.year::text, 'climatology') AS year,
  p.clamped AS mid_network_segment_months_clamped,
  p.by_month AS jan_to_dec,
  rank() OVER (ORDER BY p.clamped DESC) AS worst
FROM per_year p
ORDER BY p.year NULLS FIRST;
