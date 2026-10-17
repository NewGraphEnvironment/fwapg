-- The calendar days of the years averaged (:y1 to :y2), one row per month and day:
-- how many days of the period fall on it, and its week.
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
WITH days AS (
  SELECT extract(month FROM d)::integer AS month, extract(day FROM d)::integer AS day
  FROM generate_series(make_date(:y1, 1, 1), make_date(:y2, 12, 31), interval '1 day') AS d
)
SELECT
  month,
  day,
  count(*)::integer AS n_days,
  least((extract(doy FROM make_date(2001, month, least(day, CASE WHEN month = 2 THEN 28 ELSE 31 END)))::integer - 1) / 7 + 1, 52) AS week
FROM days
GROUP BY month, day;

ALTER TABLE fwapg.pcic_day_bins ADD PRIMARY KEY (month, day);
