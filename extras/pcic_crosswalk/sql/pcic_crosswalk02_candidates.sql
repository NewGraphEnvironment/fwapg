-- Candidate FWA positions for each PCIC outlet: up to :num_features nearest
-- streams (one per blue_line_key) within :tolerance metres of the outlet's probe
-- point, in BC.
--
-- This is FWA_IndexPoint's search (nearest 100 segments, nearest segment per
-- blue line), with segments filtered BEFORE the per-stream pick rather than after:
-- FWA_IndexPoint keeps one segment per stream and cannot exclude any but 6010, so
-- filtering its output drops the whole stream when its nearest segment is one we
-- cannot use (measured: 651 streams lost that had a usable segment within reach).
-- Excluded:
--
-- - subsurface flow construction lines (1425) and watershed group connectors (6010)
-- - streams off the network (watershed codes under 999) and segments with no
--   local code: no path along the network reaches them
-- - segments with no fundamental watershed (no upstream area to split flow by)
--
-- Side channels. A candidate on a side channel also gets its main stem as a
-- candidate (the nearest usable point on the watershed_key line within 1 km of
-- the probe point), and the vote in pcic_crosswalk04_select.sql chooses. For that
-- vote the main-stem point counts as near as the side channel it came from
-- (near_distance), so the outlets above an outlet in a braided reach can vote for
-- the main stem they are on. Outlets left on side channels in the Columbia
-- Wetlands made the 230 outlets above them unplaceable; but FWA often codes a
-- tributary's last reach as a side channel of the river it joins, and moving
-- every side-channel candidate outright put 326 tributary outlets on the big
-- river (median 68 times PCIC's flow). A tributary that enters through the side
-- channel reaches both points, and the tie goes to the nearer side channel.

DROP TABLE IF EXISTS fwapg.pcic_candidates;

CREATE TABLE fwapg.pcic_candidates AS
SELECT
  o.subid,
  row_number() OVER (PARTITION BY o.subid ORDER BY c.distance_to_stream, c.linear_feature_id) AS candidate_rank,
  c.*
FROM fwapg.pcic_outlets o
CROSS JOIN LATERAL (
  SELECT *
  FROM (
    SELECT DISTINCT ON (s.blue_line_key)
      s.linear_feature_id,
      s.blue_line_key,
      s.downstream_route_measure
        + ST_LineLocatePoint(ST_LineMerge(s.geom), o.probe_geom) * s.length_metre AS downstream_route_measure,
      s.wscode_ltree,
      s.localcode_ltree,
      ST_Distance(s.geom, o.probe_geom) AS distance_to_stream,
      ST_Distance(s.geom, o.probe_geom) AS near_distance,
      s.edge_type,
      s.watershed_key,
      s.watershed_group_code
    FROM (
      SELECT s.*
      FROM whse_basemapping.fwa_stream_networks_sp s
      WHERE s.edge_type NOT IN (1425, 6010)
      AND s.localcode_ltree IS NOT NULL
      AND NOT s.wscode_ltree <@ '999'
      AND EXISTS (
        SELECT 1 FROM whse_basemapping.fwa_streams_watersheds_lut l
        WHERE l.linear_feature_id = s.linear_feature_id
      )
      ORDER BY s.geom <-> o.probe_geom
      LIMIT 100
    ) s
    -- a probe on a vertex two segments share is equally near both: take the one
    -- starting there (FWA measures run [downstream, upstream)), which at a
    -- tributary junction is the segment above it; untied, the plan chose
    ORDER BY s.blue_line_key, ST_Distance(s.geom, o.probe_geom), s.downstream_route_measure DESC, s.linear_feature_id
  ) nearest_per_stream
  WHERE distance_to_stream <= :tolerance
  ORDER BY distance_to_stream, linear_feature_id
  LIMIT :num_features
) c
WHERE EXISTS (
  SELECT 1 FROM whse_basemapping.fwa_watershed_groups_poly w
  WHERE ST_Intersects(o.probe_geom, w.geom)
);

CREATE TEMPORARY TABLE side_moves AS
SELECT
  c.subid,
  c.distance_to_stream AS side_distance,
  m.*
FROM fwapg.pcic_candidates c
INNER JOIN fwapg.pcic_outlets o ON o.subid = c.subid
CROSS JOIN LATERAL (
  SELECT
    s.linear_feature_id,
    s.blue_line_key,
    s.downstream_route_measure
      + ST_LineLocatePoint(ST_LineMerge(s.geom), o.probe_geom) * s.length_metre AS downstream_route_measure,
    s.wscode_ltree,
    s.localcode_ltree,
    ST_Distance(s.geom, o.probe_geom) AS distance_to_stream,
    s.edge_type,
    s.watershed_key,
    s.watershed_group_code
  FROM whse_basemapping.fwa_stream_networks_sp s
  WHERE s.blue_line_key = c.watershed_key
  AND s.edge_type NOT IN (1425, 6010)
  AND s.localcode_ltree IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM whse_basemapping.fwa_streams_watersheds_lut l
    WHERE l.linear_feature_id = s.linear_feature_id
  )
  AND ST_DWithin(s.geom, o.probe_geom, 1000)
  ORDER BY ST_Distance(s.geom, o.probe_geom), s.downstream_route_measure DESC, s.linear_feature_id
  LIMIT 1
) m
WHERE c.blue_line_key != c.watershed_key;

INSERT INTO fwapg.pcic_candidates
  (subid, candidate_rank, linear_feature_id, blue_line_key, downstream_route_measure, wscode_ltree,
   localcode_ltree, distance_to_stream, near_distance, edge_type, watershed_key, watershed_group_code)
SELECT
  subid, NULL, linear_feature_id, blue_line_key, downstream_route_measure, wscode_ltree,
  localcode_ltree, distance_to_stream, side_distance, edge_type, watershed_key, watershed_group_code
FROM side_moves;

-- a main-stem point that duplicates an existing candidate's blue line keeps the
-- better of their near distances
UPDATE fwapg.pcic_candidates c
SET near_distance = d.near_distance
FROM (
  SELECT subid, blue_line_key, min(near_distance) AS near_distance
  FROM fwapg.pcic_candidates GROUP BY subid, blue_line_key
) d
WHERE c.subid = d.subid AND c.blue_line_key = d.blue_line_key;

-- one candidate per blue line again, the nearest (an added main-stem point can
-- land on the same segment as an existing candidate, at the same distance: ctid
-- breaks the tie)
DELETE FROM fwapg.pcic_candidates c
USING fwapg.pcic_candidates d
WHERE c.subid = d.subid
AND c.blue_line_key = d.blue_line_key
AND (c.distance_to_stream, c.linear_feature_id, c.ctid) > (d.distance_to_stream, d.linear_feature_id, d.ctid);

-- re-rank
UPDATE fwapg.pcic_candidates c
SET candidate_rank = r.rank
FROM (
  SELECT subid, linear_feature_id,
    row_number() OVER (PARTITION BY subid ORDER BY distance_to_stream, linear_feature_id) AS rank
  FROM fwapg.pcic_candidates
) r
WHERE c.subid = r.subid AND c.linear_feature_id = r.linear_feature_id;

CREATE INDEX ON fwapg.pcic_candidates (subid, candidate_rank);
ANALYZE fwapg.pcic_candidates;
