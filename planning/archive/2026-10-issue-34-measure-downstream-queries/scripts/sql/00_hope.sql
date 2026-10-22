-- The shipped trace from Hope (Fraser, blue line 356364114, measure 160400),
-- re-run warm: one warm-up, then three timed runs. The planning probe's 6.8 s
-- had no recorded cache state.

CREATE TEMPORARY TABLE hope_runs (rep integer, rows bigint, ms double precision);

DO $$
DECLARE
  t0 timestamptz;
  n bigint;
BEGIN
  FOR r IN 0..3 LOOP
    t0 := clock_timestamp();
    SELECT count(*) INTO n FROM whse_basemapping.fwa_downstreamtrace(356364114, 160400);
    INSERT INTO hope_runs VALUES (r, n, extract(epoch FROM clock_timestamp() - t0) * 1000);
  END LOOP;
END $$;

SELECT 'hope trace rep ' || rep || CASE WHEN rep = 0 THEN ' (warm-up)' ELSE '' END,
  format('%s rows, %s ms', rows, round(ms::numeric, 1))
FROM hope_runs
ORDER BY rep;

SELECT 'hope trace median of 3', round(percentile_cont(0.5) WITHIN GROUP (ORDER BY ms)::numeric, 1) || ' ms'
FROM hope_runs
WHERE rep > 0;
