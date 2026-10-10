-- Monthly flow for each FWA stream segment in watershed group :wsg.
--
-- A segment belongs to the sub-basin of the nearest placed PCIC outlet on or
-- below it: walking down its own blue line from the segment itself, then its path
-- (fwapg.blk_paths), the first blue line with a placed outlet, and on it the
-- highest one (the order fwa_parent_subid uses, see pcic_crosswalk06_subbasins.sql).
-- Its flow is the accumulated flow of the outlets directly above that sub-basin
-- whose water passes the segment, plus the flow generated in the sub-basin scaled
-- by the share of the sub-basin's local FWA area that drains to the segment:
--
--   q = sum(q_acc of outlets above) + q_local * (A - sum(A of those outlets)) / A_local
--
-- At the segment an outlet is placed on, every outlet directly above is above the
-- segment and the share is 1, so q is the outlet's accumulated flow there. The
-- share is set to 1 on that segment outright, because A_local can be <= 0 where
-- the outlets map to the same fundamental watershed. Local flow can be negative
-- (a losing month), so q is clamped at zero.

BEGIN;

SET LOCAL max_parallel_workers_per_gather = 0;

-- placed outlets with the start of their segment (seg_measure): on one blue line,
-- a segment belongs to the highest outlet on it or below it, compared by segment
-- so that an outlet whose measure falls on a segment end stays with its segment
CREATE TEMPORARY TABLE outlets ON COMMIT DROP AS
SELECT x.subid, x.blue_line_key, x.downstream_route_measure, x.depth, x.fwa_parent_subid, s.downstream_route_measure AS seg_measure
FROM whse_basemapping.pcic_fwa_crosswalk x
INNER JOIN whse_basemapping.fwa_stream_networks_sp s ON s.linear_feature_id = x.linear_feature_id
WHERE x.flag IS NULL;
CREATE INDEX ON outlets (blue_line_key, seg_measure);
CREATE INDEX ON outlets (fwa_parent_subid);
ANALYZE outlets;

CREATE TEMPORARY TABLE pcic_segments ON COMMIT DROP AS
WITH segments AS (
  SELECT
    s.linear_feature_id,
    s.blue_line_key,
    s.downstream_route_measure,
    s.upstream_route_measure,
    ua.upstream_area_ha
  FROM whse_basemapping.fwa_stream_networks_sp s
  INNER JOIN whse_basemapping.fwa_streams_watersheds_lut l ON s.linear_feature_id = l.linear_feature_id
  INNER JOIN whse_basemapping.fwa_watersheds_upstream_area ua ON l.watershed_feature_id = ua.watershed_feature_id
  WHERE s.watershed_group_code = :'wsg'
),
steps AS (
  -- step 0: the segment's own blue line, outlets on this segment or below it
  SELECT s.linear_feature_id, 0::bigint AS step, s.blue_line_key AS blk, s.downstream_route_measure AS measure
  FROM segments s
  UNION ALL
  -- step i: the i-th blue line on its path, at or below where its water joins
  SELECT s.linear_feature_id, u.step, u.blk, u.measure
  FROM segments s
  INNER JOIN fwapg.blk_paths bp ON bp.blue_line_key = s.blue_line_key
  CROSS JOIN LATERAL unnest(bp.path_blks, bp.path_measures) WITH ORDINALITY AS u(blk, measure, step)
),
nearest AS (
  SELECT DISTINCT ON (st.linear_feature_id)
    st.linear_feature_id,
    o.subid
  FROM steps st
  INNER JOIN outlets o
    ON o.blue_line_key = st.blk
    AND (
      (st.step = 0 AND o.seg_measure <= st.measure)
      OR (st.step > 0 AND o.downstream_route_measure <= st.measure)
    )
  ORDER BY st.linear_feature_id, st.step, o.seg_measure DESC, o.downstream_route_measure DESC, o.depth DESC, o.subid DESC
)
SELECT s.*, n.subid
FROM segments s
INNER JOIN nearest n ON s.linear_feature_id = n.linear_feature_id;

CREATE TEMPORARY TABLE pcic_segment_shares ON COMMIT DROP AS
SELECT
  s.linear_feature_id,
  s.subid,
  array_remove(array_agg(c.subid), NULL) AS upstream_subids,
  CASE
    WHEN s.linear_feature_id = sb.linear_feature_id THEN 1
    WHEN sb.local_area_ha > 0 THEN
      least(greatest((s.upstream_area_ha - coalesce(sum(cb.upstream_area_ha), 0)) / sb.local_area_ha, 0), 1)
    ELSE 0
  END AS share
FROM pcic_segments s
INNER JOIN fwapg.pcic_subbasins sb ON s.subid = sb.subid
-- outlets directly above the sub-basin whose water passes the segment: on its
-- blue line, on this segment or above it; otherwise joining it at or above it
LEFT JOIN outlets c
  ON c.fwa_parent_subid = s.subid
  AND (
    (c.blue_line_key = s.blue_line_key AND c.seg_measure >= s.downstream_route_measure)
    OR (c.blue_line_key != s.blue_line_key
      AND fwapg.blk_on_or_upstream(s.blue_line_key, s.downstream_route_measure, c.blue_line_key, c.downstream_route_measure))
  )
LEFT JOIN fwapg.pcic_subbasins cb ON c.subid = cb.subid
GROUP BY s.linear_feature_id, s.subid, s.upstream_area_ha, sb.linear_feature_id, sb.local_area_ha;

INSERT INTO whse_basemapping.fwa_stream_networks_discharge_monthly
  (linear_feature_id, watershed_group_code, month, q_m3s)
SELECT
  s.linear_feature_id,
  :'wsg',
  m.month,
  round(greatest(
    coalesce((
      SELECT sum(u.q_acc)
      FROM fwapg.pcic_subbasins_monthly u
      WHERE u.subid = ANY(s.upstream_subids)
      AND u.month = m.month
    ), 0)
    + m.q_local * s.share,
  0)::numeric, 5)
FROM pcic_segment_shares s
INNER JOIN fwapg.pcic_subbasins_monthly m ON s.subid = m.subid
ON CONFLICT DO NOTHING;

COMMIT;
