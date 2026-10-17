-- The 366 calendar days, one row per month and day: how many days of the years
-- averaged (:y1 to :y2) fall on it (0 for Feb 29 in a period with no leap year),
-- and its week.
--
-- n_days weights a day when its means are averaged over a longer period: a mean
-- over a month or week is sum(q * n_days) / sum(n_days), which equals the mean
-- of every day in it (Feb 29 occurs only in leap years).
--
-- A week is a fixed run of calendar days, the same in every year: week 1 is
-- Jan 1-7, and so on in 7-day steps of a 365-day year, with week 52 taking
-- Dec 24-31 (8 days). Feb 29 takes Feb 28's place, in week 9 (Feb 26 - Mar 4).
-- Not an ISO week, which shifts by up to 3 days from year to year and has a
-- week 53 in some years.

DROP TABLE IF EXISTS fwapg.pcic_day_bins;

CREATE TABLE fwapg.pcic_day_bins AS
WITH calendar AS (
  -- all 366 calendar days, from a leap year, whether or not the period has a Feb 29
  SELECT extract(month FROM d)::integer AS month, extract(day FROM d)::integer AS day
  FROM generate_series('2000-01-01'::date, '2000-12-31'::date, interval '1 day') AS d
),
days AS (
  SELECT extract(month FROM d)::integer AS month, extract(day FROM d)::integer AS day, count(*)::integer AS n_days
  FROM generate_series(make_date(:y1, 1, 1), make_date(:y2, 12, 31), interval '1 day') AS d
  GROUP BY 1, 2
)
SELECT
  c.month,
  c.day,
  coalesce(d.n_days, 0) AS n_days,
  least((extract(doy FROM make_date(2001, c.month, least(c.day, CASE WHEN c.month = 2 THEN 28 ELSE 31 END)))::integer - 1) / 7 + 1, 52) AS week
FROM calendar c
LEFT JOIN days d ON d.month = c.month AND d.day = c.day;

ALTER TABLE fwapg.pcic_day_bins ADD PRIMARY KEY (month, day);
