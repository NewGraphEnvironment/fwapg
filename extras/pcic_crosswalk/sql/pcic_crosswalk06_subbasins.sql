-- Per placed PCIC outlet (a sub-basin on the FWA): its FWA parent, its local FWA
-- area and, per month, the flow generated inside it and the flow accumulated at it.
--
-- PCIC's network and the FWA do not always join streams at the same place: a
-- tributary can enter the mainstem below a PCIC outlet in PCIC's network and
-- above it on the FWA. So PCIC's outflows are not accumulated as they stand.
-- Instead:
--
-- 1. Each PCIC outlet's local runoff is its outflow minus its PCIC children's
--    outflow (not clamped: routing can lose water in a month, and clamping would
--    add flow at every losing step).
-- 2. That runoff belongs to the placed outlet's sub-basin: the outlet itself if
--    placed, otherwise its anchor (its nearest placed PCIC ancestor). An unplaced
--    outlet with no placed ancestor is downstream of everything placed, outside
--    BC or at sea, and its runoff is dropped.
-- 3. Flow is accumulated down the FWA tree of placed outlets (fwa_parent_subid).
--
-- Where the two networks agree, the accumulated flow at an outlet is PCIC's
-- outflow; where they do not, flow follows the FWA. qa.sql measures how often
-- they agree.

-- fwa_parent_subid: the nearest placed outlet downstream on the FWA, found by
-- walking the outlet's own blue line down, then its path (fwapg.pcic_blk_paths)
-- to the sea: the first blue line with a placed outlet at or below the outlet's
-- position, and on it the highest such outlet (by segment, then measure). At the
-- same point, the outlet nearer PCIC's root is below. This is the order pcic_crosswalk07_segments.sql
-- assigns segments in.
CREATE INDEX IF NOT EXISTS pcic_fwa_crosswalk_blk_idx
  ON whse_basemapping.pcic_fwa_crosswalk (blue_line_key, downstream_route_measure);

UPDATE whse_basemapping.pcic_fwa_crosswalk x
SET fwa_parent_subid = p.parent
FROM (
  WITH placed AS (
    -- seg_measure: where the outlet's segment starts. On one blue line outlets are
    -- compared by segment, then by measure, so an outlet whose measure falls on a
    -- segment end is not put on the other side of the outlets on its segment.
    SELECT x.*, s.downstream_route_measure AS seg_measure
    FROM whse_basemapping.pcic_fwa_crosswalk x
    INNER JOIN whse_basemapping.fwa_stream_networks_sp s ON s.linear_feature_id = x.linear_feature_id
    WHERE x.flag IS NULL
  ),
  steps AS (
    -- step 0: the outlet's own blue line, below it
    SELECT c.subid, c.depth, 0::bigint AS step, c.blue_line_key AS blk, c.seg_measure, c.downstream_route_measure AS measure
    FROM placed c
    UNION ALL
    -- step i: the i-th blue line on its path, at or below where its water joins
    SELECT c.subid, c.depth, u.step, u.blk, NULL, u.measure
    FROM placed c
    INNER JOIN fwapg.pcic_blk_paths bp ON bp.blue_line_key = c.blue_line_key
    CROSS JOIN LATERAL unnest(bp.path_blks, bp.path_measures) WITH ORDINALITY AS u(blk, measure, step)
  )
  SELECT DISTINCT ON (st.subid)
    st.subid,
    o.subid AS parent
  FROM steps st
  INNER JOIN placed o
    ON o.blue_line_key = st.blk
    AND o.subid != st.subid
    AND (
      (st.step = 0 AND
        (o.seg_measure, o.downstream_route_measure, o.depth, o.subid) < (st.seg_measure, st.measure, st.depth, st.subid))
      OR (st.step > 0 AND o.downstream_route_measure <= st.measure)
    )
  ORDER BY st.subid, st.step, o.seg_measure DESC, o.downstream_route_measure DESC, o.depth DESC, o.subid DESC
) p
WHERE x.subid = p.subid;

CREATE INDEX IF NOT EXISTS pcic_fwa_crosswalk_fwa_parent_idx ON whse_basemapping.pcic_fwa_crosswalk (fwa_parent_subid);
ANALYZE whse_basemapping.pcic_fwa_crosswalk;

-- local FWA area: upstream area at the outlet's segment minus that at the outlets
-- directly above it on the FWA (which do not nest, being each other's siblings)
DROP TABLE IF EXISTS fwapg.pcic_subbasins;

CREATE TABLE fwapg.pcic_subbasins AS
WITH area AS (
  SELECT
    x.subid,
    x.fwa_parent_subid,
    x.linear_feature_id,
    ua.upstream_area_ha
  FROM whse_basemapping.pcic_fwa_crosswalk x
  INNER JOIN whse_basemapping.fwa_streams_watersheds_lut l ON x.linear_feature_id = l.linear_feature_id
  INNER JOIN whse_basemapping.fwa_watersheds_upstream_area ua ON l.watershed_feature_id = ua.watershed_feature_id
  WHERE x.flag IS NULL
)
SELECT
  s.subid,
  s.linear_feature_id,
  s.upstream_area_ha,
  -- can be <= 0 where an outlet and those above it map to the same fundamental watershed
  s.upstream_area_ha - coalesce(sum(c.upstream_area_ha), 0) AS local_area_ha
FROM area s
LEFT JOIN area c ON c.fwa_parent_subid = s.subid
GROUP BY s.subid, s.linear_feature_id, s.upstream_area_ha;

ALTER TABLE fwapg.pcic_subbasins ADD PRIMARY KEY (subid);

-- flow generated inside each placed outlet's sub-basin, per month
DROP TABLE IF EXISTS fwapg.pcic_subbasins_monthly;

CREATE TABLE fwapg.pcic_subbasins_monthly AS
WITH runoff AS (
  SELECT
    o.subid,
    q.month,
    q.q_m3s - coalesce(sum(qc.q_m3s), 0) AS q_runoff
  FROM fwapg.pcic_outlets o
  INNER JOIN fwapg.pcic_outlet_monthly q ON o.subid = q.subid
  LEFT JOIN fwapg.pcic_outlets c ON c.dowsubid = o.subid
  LEFT JOIN fwapg.pcic_outlet_monthly qc ON qc.subid = c.subid AND qc.month = q.month
  GROUP BY o.subid, q.month, q.q_m3s
)
SELECT
  sb.subid,
  r.month,
  sum(r.q_runoff) AS q_local
FROM runoff r
INNER JOIN whse_basemapping.pcic_fwa_crosswalk x ON r.subid = x.subid
INNER JOIN fwapg.pcic_subbasins sb
  ON sb.subid = CASE WHEN x.flag IS NULL THEN x.subid ELSE x.anchor_subid END
GROUP BY sb.subid, r.month;

ALTER TABLE fwapg.pcic_subbasins_monthly ADD PRIMARY KEY (subid, month);

-- flow accumulated at each placed outlet: its own local flow plus the
-- accumulated flow of the outlets directly above it, resolved from the top of the
-- FWA tree down. Every placed outlet must be reachable from a root, or the parent
-- relation has a cycle and accumulation would never finish.
ALTER TABLE fwapg.pcic_subbasins ADD COLUMN fwa_depth integer;

WITH RECURSIVE tree AS (
  SELECT x.subid, 0 AS fwa_depth
  FROM whse_basemapping.pcic_fwa_crosswalk x
  INNER JOIN fwapg.pcic_subbasins sb ON sb.subid = x.subid
  WHERE x.fwa_parent_subid IS NULL
  UNION ALL
  SELECT x.subid, t.fwa_depth + 1
  FROM tree t
  INNER JOIN whse_basemapping.pcic_fwa_crosswalk x ON x.fwa_parent_subid = t.subid
  INNER JOIN fwapg.pcic_subbasins sb ON sb.subid = x.subid
)
UPDATE fwapg.pcic_subbasins sb
SET fwa_depth = t.fwa_depth
FROM tree t
WHERE sb.subid = t.subid;

ALTER TABLE fwapg.pcic_subbasins_monthly ADD COLUMN q_acc double precision;

DO $$
DECLARE
  d integer;
  maxdepth integer;
  unreached integer;
BEGIN
  SELECT count(*) INTO unreached FROM fwapg.pcic_subbasins WHERE fwa_depth IS NULL;
  IF unreached > 0 THEN
    RAISE EXCEPTION '% placed outlets are not reachable from a root of the FWA parent tree (a cycle)', unreached;
  END IF;

  SELECT max(fwa_depth) INTO maxdepth FROM fwapg.pcic_subbasins;
  FOR d IN REVERSE maxdepth..0 LOOP
    UPDATE fwapg.pcic_subbasins_monthly m
    SET q_acc = m.q_local + coalesce((
      SELECT sum(cm.q_acc)
      FROM whse_basemapping.pcic_fwa_crosswalk c
      INNER JOIN fwapg.pcic_subbasins_monthly cm ON cm.subid = c.subid AND cm.month = m.month
      WHERE c.fwa_parent_subid = m.subid
    ), 0)
    FROM fwapg.pcic_subbasins sb
    WHERE sb.subid = m.subid
    AND sb.fwa_depth = d;
  END LOOP;
END $$;

ANALYZE fwapg.pcic_subbasins;
ANALYZE fwapg.pcic_subbasins_monthly;
