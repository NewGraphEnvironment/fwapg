-- Outlet and sub-basin flow averaged over each :step (month or week) of the run's
-- daily climatology, into fwapg.pcic_outlet_:table and fwapg.pcic_subbasins_:table
-- (:table is monthly or weekly). A day's mean counts by the number of days of the
-- period it holds (fwapg.pcic_day_bins.n_days), so a period's mean is the mean of
-- every day in it.

DROP TABLE IF EXISTS fwapg.pcic_outlet_:table, fwapg.pcic_subbasins_:table;

CREATE TABLE fwapg.pcic_outlet_:table AS
SELECT q.subid, b.:step, sum(q.q_m3s * b.n_days) / sum(b.n_days) AS q_m3s
FROM fwapg.pcic_outlet_daily q
INNER JOIN fwapg.pcic_day_bins b ON b.month = q.month AND b.day = q.day
GROUP BY q.subid, b.:step;

ALTER TABLE fwapg.pcic_outlet_:table ADD PRIMARY KEY (subid, :step);

CREATE TABLE fwapg.pcic_subbasins_:table AS
SELECT
  d.subid,
  b.:step,
  sum(d.q_local * b.n_days) / sum(b.n_days) AS q_local,
  sum(d.q_acc * b.n_days) / sum(b.n_days) AS q_acc
FROM fwapg.pcic_subbasins_daily d
INNER JOIN fwapg.pcic_day_bins b ON b.month = d.month AND b.day = d.day
GROUP BY d.subid, b.:step;

ALTER TABLE fwapg.pcic_subbasins_:table ADD PRIMARY KEY (subid, :step);

ANALYZE fwapg.pcic_outlet_:table;
ANALYZE fwapg.pcic_subbasins_:table;
