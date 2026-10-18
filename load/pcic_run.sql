-- One run's rows of pcic.:table (subbasin_daily, discharge_monthly or
-- discharge_weekly), read as csv from standard input, e.g.
--
--   curl -sSf https://fresh-bc.s3.us-west-2.amazonaws.com/fwapg/extras/pcic.discharge_weekly.pnwnamet_historical_1981-2010.csv.gz \
--     | gunzip | psql $DATABASE_URL -v ON_ERROR_STOP=1 -v table=discharge_weekly -f load/pcic_run.sql
--
-- Needs load/pcic.sql first: the file must match its run's row in pcic.runs
-- (rows, keys and the sum of flow at 6 decimals), so a truncated download is
-- refused, and the run must be built on the crosswalk in pcic.fwa_crosswalk. Then
-- the run's rows are replaced, in one transaction.
BEGIN;

  CREATE TEMPORARY TABLE incoming (LIKE pcic.:table) ON COMMIT DROP;
  \copy incoming FROM pstdin with (format csv, header match)
  CREATE TEMPORARY TABLE loading ON COMMIT DROP AS SELECT :'table'::text AS table_name;

  DO $$
  DECLARE
    t text := (SELECT table_name FROM loading);
    prefix text;
    n bigint;
    got_rows bigint;
    got_keys bigint;
    got_sum numeric;
    want_rows bigint;
    want_keys bigint;
    want_sum numeric;
    want_md5 text;
  BEGIN
    prefix := CASE t WHEN 'subbasin_daily' THEN 'daily' WHEN 'discharge_monthly' THEN 'monthly' WHEN 'discharge_weekly' THEN 'weekly' END;
    IF prefix IS NULL THEN
      RAISE EXCEPTION 'table must be subbasin_daily, discharge_monthly or discharge_weekly, not %', t;
    END IF;
    SELECT count(*) INTO n FROM (SELECT DISTINCT model, scenario, period FROM incoming) r;
    IF n != 1 THEN
      RAISE EXCEPTION 'the file holds % runs, not one', n;
    END IF;
    EXECUTE format('SELECT count(*), count(DISTINCT %I), sum(round(%I::numeric, 6)) FROM incoming',
      CASE prefix WHEN 'daily' THEN 'subid' ELSE 'linear_feature_id' END,
      CASE prefix WHEN 'daily' THEN 'q_acc' ELSE 'q_m3s' END)
    INTO got_rows, got_keys, got_sum;
    EXECUTE format('SELECT r.%I, r.%I, r.%I, r.crosswalk_md5 FROM pcic.runs r
      WHERE (r.model, r.scenario, r.period) = (SELECT DISTINCT model, scenario, period FROM incoming)',
      prefix || '_rows', prefix || CASE prefix WHEN 'daily' THEN '_subbasins' ELSE '_segments' END, prefix || '_q_sum')
    INTO want_rows, want_keys, want_sum, want_md5;
    IF want_md5 IS NULL THEN
      RAISE EXCEPTION 'the file''s run is not in pcic.runs: run load/pcic.sql first';
    END IF;
    IF (got_rows, got_keys, got_sum) IS DISTINCT FROM (want_rows, want_keys, want_sum) THEN
      RAISE EXCEPTION 'the file (% rows, % keys, sum %) does not match pcic.runs (% rows, % keys, sum %)',
        got_rows, got_keys, got_sum, want_rows, want_keys, want_sum;
    END IF;
    IF want_md5 IS DISTINCT FROM (SELECT md5(string_agg(x::text, '|' ORDER BY x.subid)) FROM pcic.fwa_crosswalk x) THEN
      RAISE EXCEPTION 'the run was built on another crosswalk than pcic.fwa_crosswalk: run load/pcic.sql first';
    END IF;
  END $$;

  DELETE FROM pcic.:table p USING (SELECT DISTINCT model, scenario, period FROM incoming) i
  WHERE (p.model, p.scenario, p.period) = (i.model, i.scenario, i.period);
  INSERT INTO pcic.:table SELECT * FROM incoming;

COMMIT;

ANALYZE pcic.:table;
