-- Replace the per-year days catalogue of (:model, :scenario) in pcic.series, in
-- one transaction, from fwapg.pcic_series_files: one line per parquet file in the
-- job's days directory, as pcic_days.py fingerprint prints it, with the crosswalk
-- md5 and commit each file's metadata names. :years lists every year of the
-- model's series (comma-separated).
--
-- Refused: a crosswalk unlike the one every run in pcic.runs was built on, a file
-- routed on another crosswalk than that, a year of the series with no file, a
-- file of a year outside the series, and a file whose sub-basins are not the
-- crosswalk's placed outlets or whose rows are not one per sub-basin and day.

BEGIN;

CREATE TEMPORARY TABLE series_run ON COMMIT DROP AS
SELECT
  :'model'::text AS model,
  :'scenario'::text AS scenario,
  string_to_array(:'years', ',')::integer[] AS years,
  (SELECT md5(string_agg(x::text, '|' ORDER BY x.subid)) FROM pcic.fwa_crosswalk x) AS crosswalk_md5,
  (SELECT count(*) FROM pcic.fwa_crosswalk WHERE flag IS NULL) AS placed;

DO $$
DECLARE
  bad text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pcic.runs) THEN
    RAISE EXCEPTION 'pcic.runs lists no run, so no crosswalk is published to route the days on';
  END IF;
  SELECT string_agg(DISTINCT r.model || ' / ' || r.scenario || ' / ' || r.period, ', ') INTO bad
  FROM pcic.runs r, series_run n
  WHERE r.crosswalk_md5 IS DISTINCT FROM n.crosswalk_md5;
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'pcic.fwa_crosswalk is not the crosswalk runs % were built on', bad;
  END IF;
  SELECT string_agg(f.year::text, ', ' ORDER BY f.year) INTO bad
  FROM fwapg.pcic_series_files f, series_run n
  WHERE f.crosswalk_md5 IS DISTINCT FROM n.crosswalk_md5;
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'files of years % were routed on another crosswalk than pcic.fwa_crosswalk', bad;
  END IF;
  SELECT string_agg(y::text, ', ' ORDER BY y) INTO bad
  FROM series_run n, unnest(n.years) AS y
  WHERE NOT EXISTS (SELECT 1 FROM fwapg.pcic_series_files f WHERE f.year = y);
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'years % of the series have no file', bad;
  END IF;
  SELECT string_agg(f.year::text, ', ' ORDER BY f.year) INTO bad
  FROM fwapg.pcic_series_files f, series_run n
  WHERE f.year != ALL (n.years);
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'files of years % are not of the series', bad;
  END IF;
  SELECT string_agg(f.year::text, ', ' ORDER BY f.year) INTO bad
  FROM fwapg.pcic_series_files f, series_run n
  WHERE f.subbasins != n.placed
  OR f.rows != f.subbasins * (make_date(f.year + 1, 1, 1) - make_date(f.year, 1, 1));
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'files of years % do not hold one row per placed outlet and day', bad;
  END IF;
END $$;

DELETE FROM pcic.series t USING series_run n WHERE (t.model, t.scenario) = (n.model, n.scenario);
INSERT INTO pcic.series (model, scenario, year, crosswalk_md5, rows, subbasins, q_local_sum, q_acc_sum, bytes, commit, built_at)
SELECT n.model, n.scenario, f.year, f.crosswalk_md5, f.rows, f.subbasins, f.q_local_sum, f.q_acc_sum, f.bytes, f.commit, now()
FROM fwapg.pcic_series_files f
CROSS JOIN series_run n;

COMMIT;
