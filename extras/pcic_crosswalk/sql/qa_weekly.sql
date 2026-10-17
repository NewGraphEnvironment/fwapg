-- QA tests for the weekly build (pcic_crosswalk.sh with WEEKLY=1), all should return
-- result = t. The monthly tests are in qa.sql.

-- week bins: each week is its 7 days (8 for week 52, Dec 24-31) in each year of
-- the period, plus Feb 29 in week 9
WITH period AS (
  SELECT
    (SELECT n_days FROM fwapg.pcic_day_bins WHERE month = 1 AND day = 1) AS years,
    coalesce((SELECT n_days FROM fwapg.pcic_day_bins WHERE month = 2 AND day = 29), 0) AS leap_days
),
weeks AS (
  SELECT week, sum(n_days) AS n_days FROM fwapg.pcic_day_bins GROUP BY week
)
SELECT 'weeks 1-52 hold 7 days a year, 8 in week 52, plus Feb 29 in week 9' AS test,
  count(*) = 52 AND bool_and(w.n_days = p.years * CASE WHEN w.week = 52 THEN 8 ELSE 7 END
    + CASE WHEN w.week = 9 THEN p.leap_days ELSE 0 END) AS result
FROM weeks w, period p;

-- the weekly and monthly means are averages of the same days: weighted by their
-- days, both give the sub-basin's annual mean, before any clamp
WITH m AS (
  SELECT s.subid, sum(s.q_acc * b.n_days) / sum(b.n_days) AS q
  FROM fwapg.pcic_subbasins_monthly s
  INNER JOIN (SELECT month, sum(n_days) AS n_days FROM fwapg.pcic_day_bins GROUP BY month) b ON b.month = s.month
  GROUP BY s.subid
),
w AS (
  SELECT s.subid, sum(s.q_acc * b.n_days) / sum(b.n_days) AS q
  FROM fwapg.pcic_subbasins_weekly s
  INNER JOIN (SELECT week, sum(n_days) AS n_days FROM fwapg.pcic_day_bins GROUP BY week) b ON b.week = s.week
  GROUP BY s.subid
)
SELECT 'sub-basin annual flow from weeks equals that from months' AS test,
  count(*) > 0 AND bool_and(abs(w.q - m.q) <= 1e-9 + 1e-12 * abs(m.q)) AS result
FROM m
INNER JOIN w ON w.subid = m.subid;

-- every segment with monthly flow has weekly flow, 52 weeks of it, none negative
SELECT 'weekly flow on the same segments as monthly' AS test,
  (SELECT count(DISTINCT linear_feature_id) FROM fwapg.pcic_discharge_weekly)
  = (SELECT count(DISTINCT linear_feature_id) FROM fwapg.pcic_discharge_monthly) AS result;

SELECT 'fifty-two weeks per segment' AS test, bool_and(n = 52) AS result
FROM (SELECT count(*) AS n FROM fwapg.pcic_discharge_weekly GROUP BY linear_feature_id) s;

SELECT 'no negative weekly flow' AS test, NOT EXISTS (
  SELECT 1 FROM fwapg.pcic_discharge_weekly WHERE q_m3s < 0
) AS result;

-- the segment an outlet is placed on carries the outlet's accumulated flow each
-- week (the uppermost outlet where several share a segment, as in qa.sql)
WITH placed AS (
  SELECT DISTINCT ON (x.linear_feature_id) x.subid, x.linear_feature_id
  FROM fwapg.pcic_fwa_crosswalk x
  WHERE x.flag IS NULL
  ORDER BY x.linear_feature_id, x.downstream_route_measure DESC, x.depth DESC, x.subid DESC
)
SELECT 'outlet segments carry accumulated weekly flow' AS test,
  bool_and(abs(d.q_m3s - greatest(m.q_acc, 0)) <= 0.001) AS result
FROM placed p
INNER JOIN fwapg.pcic_subbasins_weekly m ON m.subid = p.subid
INNER JOIN fwapg.pcic_discharge_weekly d
  ON d.linear_feature_id = p.linear_feature_id AND d.week = m.week;
