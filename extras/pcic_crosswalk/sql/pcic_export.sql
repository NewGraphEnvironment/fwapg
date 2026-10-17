-- Swap the run (:model, :scenario, :period) into the pcic schema in one
-- transaction: the shared crosswalk, weights and week bins, the run's sub-basin
-- daily flow and segment flow (weekly when :weekly is 1, otherwise the run's
-- weekly rows are removed), and its row in pcic.runs with each table's fingerprint.
--
-- The crosswalk and weights are shared by every run in the database. A run placed
-- differently (a changed FWA, or a run whose outlets with a series differ) would
-- replace them under runs built on the old ones, so the swap is refused when
-- another run in pcic.runs has a different crosswalk md5: rebuild those runs too,
-- or delete their rows from pcic.runs and their tables first.

BEGIN;

CREATE TEMPORARY TABLE run ON COMMIT DROP AS
SELECT
  :'model'::text AS model,
  :'scenario'::text AS scenario,
  :'period'::text AS period,
  (SELECT md5(string_agg(x::text, '|' ORDER BY x.subid)) FROM fwapg.pcic_fwa_crosswalk x) AS crosswalk_md5;

DO $$
DECLARE
  other text;
BEGIN
  SELECT string_agg(r.model || ' / ' || r.scenario || ' / ' || r.period, ', ') INTO other
  FROM pcic.runs r, run n
  WHERE (r.model, r.scenario, r.period) IS DISTINCT FROM (n.model, n.scenario, n.period)
  AND r.crosswalk_md5 IS DISTINCT FROM n.crosswalk_md5;
  IF other IS NOT NULL THEN
    RAISE EXCEPTION 'this run''s crosswalk differs from the one % % built on: rebuild them, or remove them from pcic.runs, first',
      other, CASE WHEN other LIKE '%,%' THEN 'were' ELSE 'was' END;
  END IF;
END $$;

TRUNCATE pcic.fwa_crosswalk, pcic.segment_weights, pcic.day_bins;
INSERT INTO pcic.fwa_crosswalk SELECT * FROM fwapg.pcic_fwa_crosswalk;
INSERT INTO pcic.segment_weights (linear_feature_id, watershed_group_code, subid, share, upstream_subids)
SELECT linear_feature_id, watershed_group_code, subid, share, upstream_subids FROM fwapg.pcic_segment_weights;
INSERT INTO pcic.day_bins (month, day, week) SELECT month, day, week FROM fwapg.pcic_day_bins;

DELETE FROM pcic.subbasin_daily t USING run n WHERE (t.model, t.scenario, t.period) = (n.model, n.scenario, n.period);
INSERT INTO pcic.subbasin_daily (model, scenario, period, subid, month, day, n_days, q_local, q_acc)
SELECT n.model, n.scenario, n.period, d.subid, d.month, d.day, b.n_days, d.q_local, d.q_acc
FROM fwapg.pcic_subbasins_daily d
INNER JOIN fwapg.pcic_day_bins b ON b.month = d.month AND b.day = d.day
CROSS JOIN run n;

DELETE FROM pcic.discharge_monthly t USING run n WHERE (t.model, t.scenario, t.period) = (n.model, n.scenario, n.period);
INSERT INTO pcic.discharge_monthly (model, scenario, period, linear_feature_id, watershed_group_code, month, q_m3s)
SELECT n.model, n.scenario, n.period, d.linear_feature_id, d.watershed_group_code, d.month, d.q_m3s
FROM fwapg.pcic_discharge_monthly d
CROSS JOIN run n;

DELETE FROM pcic.discharge_weekly t USING run n WHERE (t.model, t.scenario, t.period) = (n.model, n.scenario, n.period);
\if :weekly
INSERT INTO pcic.discharge_weekly (model, scenario, period, linear_feature_id, watershed_group_code, week, q_m3s)
SELECT n.model, n.scenario, n.period, d.linear_feature_id, d.watershed_group_code, d.week, d.q_m3s
FROM fwapg.pcic_discharge_weekly d
CROSS JOIN run n;
\endif

DELETE FROM pcic.runs t USING run n WHERE (t.model, t.scenario, t.period) = (n.model, n.scenario, n.period);
INSERT INTO pcic.runs
SELECT
  n.model,
  n.scenario,
  n.period,
  n.crosswalk_md5,
  w.n_rows, w.share_sum,
  d.n_rows, d.n_keys, d.q_sum,
  m.n_rows, m.n_keys, m.q_sum,
  k.n_rows, k.n_keys, k.q_sum,
  now()
FROM run n
CROSS JOIN LATERAL (
  SELECT count(*) AS n_rows, sum(round(share::numeric, 9)) AS share_sum FROM pcic.segment_weights
) w
CROSS JOIN LATERAL (
  SELECT count(*) AS n_rows, count(DISTINCT subid) AS n_keys, sum(round(q_acc::numeric, 6)) AS q_sum
  FROM pcic.subbasin_daily t WHERE (t.model, t.scenario, t.period) = (n.model, n.scenario, n.period)
) d
CROSS JOIN LATERAL (
  SELECT count(*) AS n_rows, count(DISTINCT linear_feature_id) AS n_keys, sum(round(q_m3s::numeric, 6)) AS q_sum
  FROM pcic.discharge_monthly t WHERE (t.model, t.scenario, t.period) = (n.model, n.scenario, n.period)
) m
CROSS JOIN LATERAL (
  SELECT nullif(count(*), 0) AS n_rows, nullif(count(DISTINCT linear_feature_id), 0) AS n_keys, sum(round(q_m3s::numeric, 6)) AS q_sum
  FROM pcic.discharge_weekly t WHERE (t.model, t.scenario, t.period) = (n.model, n.scenario, n.period)
) k;

COMMIT;

ANALYZE pcic.fwa_crosswalk;
ANALYZE pcic.segment_weights;
ANALYZE pcic.subbasin_daily;
ANALYZE pcic.discharge_monthly;
ANALYZE pcic.discharge_weekly;
