-- QA tests for the per-year sub-basin days (DAYS=1), all should return result = t.
-- Run by pcic_crosswalk.sh after the per-year loop and before the staging tables
-- are dropped; it stops before the catalogue is exported if any is f. Reports are
-- in qa_report_days.sql.
--
-- fwapg.pcic_days_means holds, per sub-basin and calendar day, the mean over the
-- years :y1 to :y2 of the published files (read back by pcic_days.py means, from
-- their float32 values) and each day's mean magnitude. Their mean equals the run's
-- climatology, fwapg.pcic_subbasins_daily, to within float32 rounding: each stored
-- value is within 2^-24 of its own magnitude, so a mean is within 2^-24 of the
-- mean magnitude, which a bin whose q_local changes sign across years (a losing
-- reach) can hold far above the mean itself. The tolerance is twice that, plus
-- 1e-9 m3/s for float64 noise.
--
-- That also closes the published monthly flow, transitively: pcic.discharge_monthly
-- is pcic_crosswalk09_discharge.sql applied to pcic_crosswalk08_periods.sql applied
-- to pcic_subbasins_daily; the mean over years and 08's n_days-weighted mean are
-- linear and commute, and 09's clamp and 5-decimal round come once, after
-- averaging, in both. So a reader averaging the files over :y1-:y2 and routing the
-- mean reproduces pcic.discharge_monthly to about 1e-7 relative, not at 5 decimals
-- row for row (a value on a rounding edge can round the other way).
--
-- When every year was built in this run (:ran_all = 1), the float64 monthly means
-- of each year (fwapg.pcic_subbasins_months, before the float32 write) are also
-- averaged over the years, each month weighted by its days in that year, and
-- compared with the run's monthly sub-basin flow at 1e-9 of the flows involved.

SELECT 'the files give every calendar day of the years averaged, once for each year' AS test,
  (SELECT count(*) FROM fwapg.pcic_days_means)
    = (SELECT count(*) FROM fwapg.pcic_subbasins_daily d INNER JOIN fwapg.pcic_day_bins b USING (month, day) WHERE b.n_days > 0)
  AND (SELECT count(*) FROM fwapg.pcic_days_means)
    = (SELECT count(*)
       FROM fwapg.pcic_days_means m
       INNER JOIN fwapg.pcic_subbasins_daily d USING (subid, month, day)
       INNER JOIN fwapg.pcic_day_bins b USING (month, day)
       WHERE m.n = b.n_days) AS result;

SELECT 'the files'' mean q_local over the years is the climatology''s, within float32 rounding' AS test,
  bool_and(abs(m.q_local - d.q_local) <= power(2, -23) * m.abs_local + 1e-9) AS result
FROM fwapg.pcic_days_means m
INNER JOIN fwapg.pcic_subbasins_daily d USING (subid, month, day);

SELECT 'the files'' mean q_acc over the years is the climatology''s, within float32 rounding' AS test,
  bool_and(abs(m.q_acc - d.q_acc) <= power(2, -23) * m.abs_acc + 1e-9) AS result
FROM fwapg.pcic_days_means m
INNER JOIN fwapg.pcic_subbasins_daily d USING (subid, month, day);

\if :ran_all
WITH years AS (
  SELECT s.subid, s.month,
    sum(s.q_local * n.n_days) / sum(n.n_days) AS q_local,
    sum(s.q_acc * n.n_days) / sum(n.n_days) AS q_acc,
    count(*) AS n_years
  FROM fwapg.pcic_subbasins_months s
  CROSS JOIN LATERAL (SELECT (make_date(s.year, s.month, 1) + interval '1 month')::date - make_date(s.year, s.month, 1) AS n_days) n
  WHERE s.year BETWEEN :y1 AND :y2
  GROUP BY s.subid, s.month
)
SELECT 'the years'' monthly means average to the run''s monthly sub-basin flow' AS test,
  count(*) = (SELECT count(*) FROM fwapg.pcic_subbasins_monthly)
  AND bool_and(y.n_years = :y2 - :y1 + 1)
  AND bool_and(abs(y.q_local - m.q_local) <= 1e-9 * (abs(m.q_local) + abs(m.q_acc)) + 1e-12)
  AND bool_and(abs(y.q_acc - m.q_acc) <= 1e-9 * (abs(m.q_local) + abs(m.q_acc)) + 1e-12) AS result
FROM years y
INNER JOIN fwapg.pcic_subbasins_monthly m USING (subid, month);
\endif
