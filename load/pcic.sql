-- PCIC routed flow on FWA streams (extras/pcic_crosswalk, NewGraph fork only): the
-- tables every run shares, from the export cached in NewGraph's fresh-bc bucket.
-- Run load/pcic_schema.sql first; load/pcic_run.sql then loads each run's rows.
--
-- pcic.runs gains (or replaces) the published runs, with the fingerprints
-- load/pcic_run.sql checks each run's file against. The crosswalk, weights and
-- week bins are replaced, after checking them against those fingerprints. A run
-- built in this database on another crosswalk would be left on the wrong one, so
-- that stops the load (as in extras/pcic_crosswalk/sql/pcic_export.sql).
-- One transaction, so a failed download or check leaves the tables as they were.
BEGIN;

  CREATE TEMPORARY TABLE runs_in (LIKE pcic.runs) ON COMMIT DROP;
  CREATE TEMPORARY TABLE crosswalk_in (LIKE pcic.fwa_crosswalk) ON COMMIT DROP;
  CREATE TEMPORARY TABLE weights_in (LIKE pcic.segment_weights) ON COMMIT DROP;
  CREATE TEMPORARY TABLE day_bins_in (LIKE pcic.day_bins) ON COMMIT DROP;

  \copy runs_in FROM PROGRAM 'curl -sSf https://fresh-bc.s3.us-west-2.amazonaws.com/fwapg/extras/pcic.runs.csv.gz | gunzip' with (format csv, header match)
  \copy crosswalk_in FROM PROGRAM 'curl -sSf https://fresh-bc.s3.us-west-2.amazonaws.com/fwapg/extras/pcic.fwa_crosswalk.csv.gz | gunzip' with (format csv, header match)
  \copy weights_in FROM PROGRAM 'curl -sSf https://fresh-bc.s3.us-west-2.amazonaws.com/fwapg/extras/pcic.segment_weights.csv.gz | gunzip' with (format csv, header match)
  \copy day_bins_in FROM PROGRAM 'curl -sSf https://fresh-bc.s3.us-west-2.amazonaws.com/fwapg/extras/pcic.day_bins.csv.gz | gunzip' with (format csv, header match)

  DO $$
  DECLARE
    cw_md5 text := (SELECT md5(string_agg(x::text, '|' ORDER BY x.subid)) FROM crosswalk_in x);
    w_rows bigint := (SELECT count(*) FROM weights_in);
    w_sum numeric := (SELECT sum(round(share::numeric, 9)) FROM weights_in);
    other text;
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
    SELECT string_agg(r.model || ' / ' || r.scenario || ' / ' || r.period, ', ') INTO other
    FROM pcic.runs r
    WHERE NOT EXISTS (SELECT 1 FROM runs_in i WHERE (i.model, i.scenario, i.period) = (r.model, r.scenario, r.period))
    AND r.crosswalk_md5 IS DISTINCT FROM cw_md5;
    IF other IS NOT NULL THEN
      RAISE EXCEPTION 'runs % in this database were built on another crosswalk: rebuild them, or remove them from pcic.runs, first', other;
    END IF;
  END $$;

  DELETE FROM pcic.runs r USING runs_in i WHERE (i.model, i.scenario, i.period) = (r.model, r.scenario, r.period);
  INSERT INTO pcic.runs SELECT * FROM runs_in;
  TRUNCATE pcic.fwa_crosswalk, pcic.segment_weights, pcic.day_bins;
  INSERT INTO pcic.fwa_crosswalk SELECT * FROM crosswalk_in;
  INSERT INTO pcic.segment_weights SELECT * FROM weights_in;
  INSERT INTO pcic.day_bins SELECT * FROM day_bins_in;

COMMIT;

ANALYZE pcic.runs;
ANALYZE pcic.fwa_crosswalk;
ANALYZE pcic.segment_weights;
