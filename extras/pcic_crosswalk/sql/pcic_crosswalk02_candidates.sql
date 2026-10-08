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
      s.edge_type,
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
    ORDER BY s.blue_line_key, ST_Distance(s.geom, o.probe_geom)
  ) nearest_per_stream
  WHERE distance_to_stream <= :tolerance
  ORDER BY distance_to_stream
  LIMIT :num_features
) c
WHERE EXISTS (
  SELECT 1 FROM whse_basemapping.fwa_watershed_groups_poly w
  WHERE ST_Intersects(o.probe_geom, w.geom)
);

CREATE INDEX ON fwapg.pcic_candidates (subid, candidate_rank);
ANALYZE fwapg.pcic_candidates;
