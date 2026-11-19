-- PCIC routed flow on FWA streams (extras/pcic_crosswalk, NewGraph fork only): the
-- tables every run shares, from the export cached in NewGraph's fresh-bc bucket.
-- Run load/pcic_schema.sql first; load/pcic_run.sql then loads each run's rows.
--
-- pcic.runs gains (or replaces) the published runs, with the fingerprints
-- load/pcic_run.sql checks each run's file against. The crosswalk, weights and
-- week bins are replaced, after checking them against those fingerprints. A run
-- built in this database on another crosswalk or weights, and not published,
-- would be left on the wrong ones, so that stops the load (as in
-- extras/pcic_crosswalk/sql/pcic_export.sql). A published run's rows already in
-- this database are kept only where they are what its published fingerprint
-- describes; the rest are deleted, so that only load/pcic_run.sql brings them back.
-- pcic.series gains (or replaces) the published per-year days catalogue, per
-- model and scenario; it may be empty, and the parquet files it describes are never
-- loaded. A catalogue built on another crosswalk than the published one stops the
-- load, as does one in this database, not published, built on another.
-- One transaction, so a failed download or check leaves the tables as they were.
BEGIN;

  CREATE TEMPORARY TABLE runs_in (LIKE pcic.runs) ON COMMIT DROP;
  CREATE TEMPORARY TABLE crosswalk_in (LIKE pcic.fwa_crosswalk) ON COMMIT DROP;
  CREATE TEMPORARY TABLE weights_in (LIKE pcic.segment_weights) ON COMMIT DROP;
  CREATE TEMPORARY TABLE day_bins_in (LIKE pcic.day_bins) ON COMMIT DROP;
  CREATE TEMPORARY TABLE series_in (LIKE pcic.series) ON COMMIT DROP;

  \copy runs_in FROM PROGRAM 'curl -sSf https://fresh-bc.s3.us-west-2.amazonaws.com/fwapg/extras/pcic.runs.csv.gz | gunzip' with (format csv, header match)
  \copy crosswalk_in FROM PROGRAM 'curl -sSf https://fresh-bc.s3.us-west-2.amazonaws.com/fwapg/extras/pcic.fwa_crosswalk.csv.gz | gunzip' with (format csv, header match)
  \copy weights_in FROM PROGRAM 'curl -sSf https://fresh-bc.s3.us-west-2.amazonaws.com/fwapg/extras/pcic.segment_weights.csv.gz | gunzip' with (format csv, header match)
  \copy day_bins_in FROM PROGRAM 'curl -sSf https://fresh-bc.s3.us-west-2.amazonaws.com/fwapg/extras/pcic.day_bins.csv.gz | gunzip' with (format csv, header match)
  \copy series_in FROM PROGRAM 'curl -sSf https://fresh-bc.s3.us-west-2.amazonaws.com/fwapg/extras/pcic.series.csv.gz | gunzip' with (format csv, header match)

  DO $$
  DECLARE
    cw_md5 text := (SELECT md5(string_agg(x::text, '|' ORDER BY x.subid)) FROM crosswalk_in x);
    w_rows bigint := (SELECT count(*) FROM weights_in);
    w_sum numeric := (SELECT sum(round(share::numeric, 9)) FROM weights_in);
    other text;
    orphan text;
  BEGIN
    IF NOT EXISTS (SELECT 1 FROM runs_in) THEN
      RAISE EXCEPTION 'pcic.runs.csv.gz lists no runs';
    END IF;
    IF EXISTS (SELECT 1 FROM runs_in WHERE crosswalk_md5 IS DISTINCT FROM cw_md5) THEN
      RAISE EXCEPTION 'pcic.fwa_crosswalk.csv.gz (md5 %) is not the crosswalk the published runs were built on', cw_md5;
    END IF;
    IF EXISTS (SELECT 1 FROM runs_in WHERE weights_rows IS DISTINCT FROM w_rows OR weights_share_sum IS DISTINCT FROM w_sum) THEN
      RAISE EXCEPTION 'pcic.segment_weights.csv.gz (% rows, share sum %) does not match pcic.runs', w_rows, w_sum;
    END IF;
    IF (SELECT count(*) FROM day_bins_in) != 366 THEN
      RAISE EXCEPTION 'pcic.day_bins.csv.gz does not hold 366 calendar days';
    END IF;
    IF EXISTS (SELECT 1 FROM series_in WHERE crosswalk_md5 IS DISTINCT FROM cw_md5) THEN
      RAISE EXCEPTION 'pcic.series.csv.gz lists days built on another crosswalk than pcic.fwa_crosswalk.csv.gz (md5 %)', cw_md5;
    END IF;
    SELECT string_agg(DISTINCT s.model || ' / ' || s.scenario, ', ') INTO other
    FROM pcic.series s
    WHERE NOT EXISTS (SELECT 1 FROM series_in i WHERE (i.model, i.scenario) = (s.model, s.scenario))
    AND s.crosswalk_md5 IS DISTINCT FROM cw_md5;
    IF other IS NOT NULL THEN
      RAISE EXCEPTION 'per-year days % in pcic.series were built on another crosswalk: rebuild them, or delete their rows from pcic.series, first', other;
    END IF;
    SELECT string_agg(r.model || ' / ' || r.scenario || ' / ' || r.period, ', ') INTO other
    FROM pcic.runs r
    WHERE NOT EXISTS (SELECT 1 FROM runs_in i WHERE (i.model, i.scenario, i.period) = (r.model, r.scenario, r.period))
    AND (r.crosswalk_md5, r.weights_rows, r.weights_share_sum) IS DISTINCT FROM (cw_md5, w_rows, w_sum);
    IF other IS NOT NULL THEN
      RAISE EXCEPTION 'runs % in this database were built on another crosswalk or weights: rebuild them, or delete their rows from pcic.runs, pcic.subbasin_daily and pcic.discharge_*, first', other;
    END IF;
    -- rows of a run that pcic.runs does not list: nothing would check or replace them
    SELECT string_agg(o.model || ' / ' || o.scenario || ' / ' || o.period, ', ') INTO orphan
    FROM (
      SELECT DISTINCT model, scenario, period FROM pcic.subbasin_daily
      UNION SELECT DISTINCT model, scenario, period FROM pcic.discharge_monthly
      UNION SELECT DISTINCT model, scenario, period FROM pcic.discharge_weekly
    ) o
    WHERE NOT EXISTS (SELECT 1 FROM pcic.runs r WHERE (r.model, r.scenario, r.period) = (o.model, o.scenario, o.period))
    AND NOT EXISTS (SELECT 1 FROM runs_in n WHERE (n.model, n.scenario, n.period) = (o.model, o.scenario, o.period));
    IF orphan IS NOT NULL THEN
      RAISE EXCEPTION 'pcic.subbasin_daily or pcic.discharge_* hold rows of runs % that pcic.runs does not list: delete them first', orphan;
    END IF;
  END $$;

  -- a published run's rows here that are not the published ones
  DELETE FROM pcic.subbasin_daily t USING runs_in i
  WHERE (t.model, t.scenario, t.period) = (i.model, i.scenario, i.period)
  AND NOT EXISTS (
    SELECT 1 FROM pcic.runs r
    WHERE (r.model, r.scenario, r.period) = (i.model, i.scenario, i.period)
    AND (r.crosswalk_md5, r.daily_rows, r.daily_subbasins, r.daily_q_sum)
      IS NOT DISTINCT FROM (i.crosswalk_md5, i.daily_rows, i.daily_subbasins, i.daily_q_sum)
  );
  DELETE FROM pcic.discharge_monthly t USING runs_in i
  WHERE (t.model, t.scenario, t.period) = (i.model, i.scenario, i.period)
  AND NOT EXISTS (
    SELECT 1 FROM pcic.runs r
    WHERE (r.model, r.scenario, r.period) = (i.model, i.scenario, i.period)
    AND (r.crosswalk_md5, r.monthly_rows, r.monthly_segments, r.monthly_q_sum)
      IS NOT DISTINCT FROM (i.crosswalk_md5, i.monthly_rows, i.monthly_segments, i.monthly_q_sum)
  );
  DELETE FROM pcic.discharge_weekly t USING runs_in i
  WHERE (t.model, t.scenario, t.period) = (i.model, i.scenario, i.period)
  AND NOT EXISTS (
    SELECT 1 FROM pcic.runs r
    WHERE (r.model, r.scenario, r.period) = (i.model, i.scenario, i.period)
    AND (r.crosswalk_md5, r.weekly_rows, r.weekly_segments, r.weekly_q_sum)
      IS NOT DISTINCT FROM (i.crosswalk_md5, i.weekly_rows, i.weekly_segments, i.weekly_q_sum)
  );
  DELETE FROM pcic.runs r USING runs_in i WHERE (i.model, i.scenario, i.period) = (r.model, r.scenario, r.period);
  INSERT INTO pcic.runs SELECT * FROM runs_in;
  TRUNCATE pcic.fwa_crosswalk, pcic.segment_weights, pcic.day_bins;
  INSERT INTO pcic.fwa_crosswalk SELECT * FROM crosswalk_in;
  INSERT INTO pcic.segment_weights SELECT * FROM weights_in;
  INSERT INTO pcic.day_bins SELECT * FROM day_bins_in;
  DELETE FROM pcic.series s USING (SELECT DISTINCT model, scenario FROM series_in) i
  WHERE (s.model, s.scenario) = (i.model, i.scenario);
  INSERT INTO pcic.series SELECT * FROM series_in;

COMMIT;

ANALYZE pcic.runs;
ANALYZE pcic.series;
ANALYZE pcic.fwa_crosswalk;
ANALYZE pcic.segment_weights;
