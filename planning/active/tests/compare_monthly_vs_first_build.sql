-- Phase 5 (#25): the rebuilt PNWNAmet 1951-2012 monthly flow in pcic.discharge_monthly
-- against the first build, still in whse_basemapping.fwa_stream_networks_discharge_monthly
-- (published by #9: 40,524,444 rows, 3,377,037 segments, sum 178035348.248310).
WITH new AS (
  SELECT linear_feature_id, month, q_m3s FROM pcic.discharge_monthly
  WHERE (model, scenario, period) = ('PNWNAmet', 'historical', '1951-2012')
)
SELECT
  count(*) FILTER (WHERE n.linear_feature_id IS NULL) AS only_in_first,
  count(*) FILTER (WHERE o.linear_feature_id IS NULL) AS only_in_new,
  count(*) FILTER (WHERE n.q_m3s != o.q_m3s) AS rows_differing,
  count(*) FILTER (WHERE abs(n.q_m3s - o.q_m3s) > 0.0000101) AS rows_differing_over_1e5,
  max(abs(n.q_m3s - o.q_m3s)) AS max_abs_diff,
  (SELECT count(*) FROM new) AS new_rows,
  (SELECT count(DISTINCT linear_feature_id) FROM new) AS new_segments,
  (SELECT sum(round(q_m3s::numeric, 6)) FROM new) AS new_sum
FROM new n
FULL JOIN whse_basemapping.fwa_stream_networks_discharge_monthly o USING (linear_feature_id, month);
