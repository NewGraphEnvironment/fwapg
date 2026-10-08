-- Choose one FWA position per PCIC outlet so that PCIC's routing chain stays
-- intact on the FWA: each outlet must sit on or upstream of
-- the position chosen for the nearest placed outlet below it, its anchor.
--
-- Resolved from each tree's root upward, one depth at a time, so an outlet is
-- always tested against an anchor that is already fixed. Among its valid
-- candidates an outlet takes the one most of the PCIC network above it agrees
-- with: the number of outlets up to three levels above it with a near candidate
-- (within 25 m of their nearest) on or upstream of it; then the nearest.
--
-- One level is not enough either way. Counting a child's far candidates put the
-- Nicola main stem's outlet on Clapperton Creek (the child's 86 m fallback tied
-- with its 8.9 m candidate on the Nicola); ignoring them put an outlet in the
-- Columbia Wetlands on a parallel channel coded as a tributary, because its only
-- child's near candidate was on that channel while every outlet above the child
-- was on the Columbia.
--
-- An outlet with no valid candidate is left unplaced and flagged, and the outlets
-- above it are tested against its own anchor instead.
--
-- Outlets listed in fwapg.pcic_demoted, and outlets with no PNWNAmet series, are
-- treated as having no valid candidate: placing an outlet with no flow would
-- carve its catchment out of the sub-basin below without carrying its flow.

DROP TABLE IF EXISTS whse_basemapping.pcic_fwa_crosswalk;

CREATE TABLE whse_basemapping.pcic_fwa_crosswalk (
  subid integer PRIMARY KEY,
  dowsubid integer,
  anchor_subid integer,          -- nearest placed outlet downstream in PCIC's tree (NULL for a root)
  fwa_parent_subid integer,      -- nearest placed outlet downstream on the FWA (set by pcic_crosswalk06_subbasins.sql)
  islake boolean,
  depth integer,
  linear_feature_id bigint,
  blue_line_key integer,
  downstream_route_measure double precision,
  wscode_ltree ltree,
  localcode_ltree ltree,
  watershed_group_code text,
  distance_to_stream double precision,
  candidate_rank integer,
  flag text                      -- NULL, 'no_candidate', 'no_series', 'broken_chain', 'demoted'
);

DO $$
DECLARE
  d integer;
  maxdepth integer;
BEGIN
  SELECT max(depth) INTO maxdepth FROM fwapg.pcic_outlets;
  FOR d IN 0..maxdepth LOOP

    INSERT INTO whse_basemapping.pcic_fwa_crosswalk
    WITH outlets AS (
      SELECT
        o.subid,
        o.dowsubid,
        o.islake,
        o.depth,
        -- the anchor is the parent if placed, otherwise the parent's anchor
        a.subid AS a_subid,
        a.blue_line_key AS a_blk,
        a.downstream_route_measure AS a_drm
      FROM fwapg.pcic_outlets o
      LEFT JOIN whse_basemapping.pcic_fwa_crosswalk p ON o.dowsubid = p.subid
      LEFT JOIN whse_basemapping.pcic_fwa_crosswalk a
        ON a.subid = CASE WHEN p.linear_feature_id IS NOT NULL THEN p.subid ELSE p.anchor_subid END
      WHERE o.depth = d
    ),

    valid AS (
      SELECT
        x.*,
        (
          SELECT count(DISTINCT v.voter)
          FROM fwapg.pcic_voters v
          WHERE v.subid = o.subid
          AND fwapg.pcic_on_or_upstream(x.blue_line_key, x.downstream_route_measure, v.blue_line_key, v.downstream_route_measure)
        ) AS score
      FROM outlets o
      INNER JOIN fwapg.pcic_candidates x ON x.subid = o.subid
      WHERE NOT EXISTS (SELECT 1 FROM fwapg.pcic_demoted dm WHERE dm.subid = x.subid)
      AND EXISTS (SELECT 1 FROM fwapg.pcic_outlet_monthly q WHERE q.subid = x.subid)
      AND (
        o.a_subid IS NULL
        OR fwapg.pcic_on_or_upstream(o.a_blk, o.a_drm, x.blue_line_key, x.downstream_route_measure)
      )
    ),

    best AS (
      SELECT DISTINCT ON (v.subid) v.*
      FROM valid v
      ORDER BY v.subid, v.score DESC, v.candidate_rank
    )

    SELECT
      o.subid,
      o.dowsubid,
      o.a_subid,
      NULL::integer,
      o.islake,
      o.depth,
      b.linear_feature_id,
      b.blue_line_key,
      b.downstream_route_measure,
      b.wscode_ltree,
      b.localcode_ltree,
      b.watershed_group_code,
      b.distance_to_stream,
      b.candidate_rank,
      CASE
        WHEN b.subid IS NOT NULL THEN NULL
        WHEN NOT EXISTS (SELECT 1 FROM fwapg.pcic_outlet_monthly q WHERE q.subid = o.subid) THEN 'no_series'
        WHEN EXISTS (SELECT 1 FROM fwapg.pcic_demoted dm WHERE dm.subid = o.subid) THEN 'demoted'
        WHEN EXISTS (SELECT 1 FROM fwapg.pcic_candidates x WHERE x.subid = o.subid) THEN 'broken_chain'
        ELSE 'no_candidate'
      END
    FROM outlets o
    LEFT JOIN best b ON o.subid = b.subid;

  END LOOP;
END $$;

CREATE INDEX ON whse_basemapping.pcic_fwa_crosswalk (anchor_subid);
CREATE INDEX ON whse_basemapping.pcic_fwa_crosswalk (linear_feature_id);
CREATE INDEX ON whse_basemapping.pcic_fwa_crosswalk USING gist (wscode_ltree);
CREATE INDEX ON whse_basemapping.pcic_fwa_crosswalk USING btree (wscode_ltree);
ANALYZE whse_basemapping.pcic_fwa_crosswalk;
