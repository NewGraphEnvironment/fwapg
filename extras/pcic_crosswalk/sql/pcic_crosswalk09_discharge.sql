-- Flow per :step (month or week) for each FWA stream segment in watershed group
-- :wsg, into fwapg.pcic_discharge_:table: the segment's weights
-- (pcic_crosswalk07_segments.sql) applied to the period's sub-basin flows
-- (pcic_crosswalk08_periods.sql),
--
--   q = greatest(sum(q_acc of upstream_subids) + q_local * share, 0)
--
-- Local flow can be negative (a losing period), so q is clamped at zero; q_raw
-- keeps the value before the clamp, for the count of clamped rows in
-- qa_report.sql. It is not exported.

INSERT INTO fwapg.pcic_discharge_:table
  (linear_feature_id, watershed_group_code, :step, q_raw, q_m3s)
SELECT
  w.linear_feature_id,
  w.watershed_group_code,
  m.:step,
  r.q,
  round(greatest(r.q, 0)::numeric, 5)
FROM fwapg.pcic_segment_weights w
INNER JOIN fwapg.pcic_subbasins_:table m ON m.subid = w.subid
CROSS JOIN LATERAL (
  SELECT
    coalesce((
      SELECT sum(u.q_acc)
      FROM fwapg.pcic_subbasins_:table u
      WHERE u.subid = ANY(w.upstream_subids)
      AND u.:step = m.:step
    ), 0)
    + m.q_local * w.share AS q
) r
WHERE w.watershed_group_code = :'wsg'
ON CONFLICT DO NOTHING;
