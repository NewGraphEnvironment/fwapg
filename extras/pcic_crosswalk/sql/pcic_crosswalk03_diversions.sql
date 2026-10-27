-- PCIC outlets whose water leaves a lake by another route than the FWA's, listed
-- by hand (NewGraphEnvironment/fwapg#24). Each is placed at the FWA's exit from
-- the lake, the lowest segment of the lake on the blue line that drains it, so the
-- outlets above it place against the FWA as usual
-- (pcic_crosswalk04_select.sql), and its water is passed to its nearest placed
-- PCIC ancestor, where PCIC sends it (pcic_crosswalk06_subbasins.sql). The FWA
-- parent its position gives it is kept here as position_parent_subid: its area is
-- that sub-basin's, its water is not (pcic_crosswalk07_segments.sql).
--
-- 1007550, the Nechako Reservoir. PCIC's tree sends the reservoir out through the
-- Skins Lake spillway and the Cheslatta River (its ancestor 1008709, at the
-- spillway gauge 08JA013); the FWA through Kenney Dam at the foot of Knewstubb
-- Lake, into the Nechako canyon. The canyon has carried almost no water since the
-- dam closed in 1952. Unlisted, every outlet above 1007550 with a candidate broke
-- the chain (479; 4 have none), and the reservoir's segments carried about 0 m3/s.

DROP TABLE IF EXISTS fwapg.pcic_diversions;

CREATE TABLE fwapg.pcic_diversions (
  subid integer PRIMARY KEY,
  blue_line_key integer NOT NULL,     -- the FWA line that drains the lake
  waterbody_key integer NOT NULL,     -- the lake: its lowest segment on that line is the exit
  note text NOT NULL,
  -- derived below: the exit
  linear_feature_id bigint,
  downstream_route_measure double precision,
  wscode_ltree ltree,
  localcode_ltree ltree,
  watershed_group_code text,
  distance_to_stream double precision,
  -- set by pcic_crosswalk06_subbasins.sql
  position_parent_subid integer
);

INSERT INTO fwapg.pcic_diversions (subid, blue_line_key, waterbody_key, note)
VALUES
  (1007550, 356362759, 329318438, 'Nechako Reservoir: PCIC routes it through the Skins Lake spillway and the Cheslatta, the FWA through Kenney Dam');

UPDATE fwapg.pcic_diversions dv
SET
  linear_feature_id = e.linear_feature_id,
  downstream_route_measure = e.downstream_route_measure,
  wscode_ltree = e.wscode_ltree,
  localcode_ltree = e.localcode_ltree,
  watershed_group_code = e.watershed_group_code,
  distance_to_stream = e.distance_to_stream
FROM (
  SELECT d.subid, s.linear_feature_id, s.downstream_route_measure, s.wscode_ltree, s.localcode_ltree,
    s.watershed_group_code, ST_Distance(s.geom, o.probe_geom) AS distance_to_stream
  FROM fwapg.pcic_diversions d
  INNER JOIN fwapg.pcic_outlets o ON o.subid = d.subid
  CROSS JOIN LATERAL (
    SELECT s.*
    FROM whse_basemapping.fwa_stream_networks_sp s
    WHERE s.blue_line_key = d.blue_line_key
    AND s.waterbody_key = d.waterbody_key
    ORDER BY s.downstream_route_measure
    LIMIT 1
  ) s
) e
WHERE e.subid = dv.subid;

-- refuse a listed outlet that is not a PCIC lake outlet with a series, and an exit
-- that is not on the line or that placement could not use (as pcic_crosswalk02_candidates.sql
-- excludes: subsurface flow, off the network, no local code, no fundamental watershed)
DO $$
DECLARE
  bad text;
BEGIN
  SELECT string_agg(dv.subid::text, ', ') INTO bad
  FROM fwapg.pcic_diversions dv
  LEFT JOIN fwapg.pcic_outlets o ON o.subid = dv.subid
  WHERE o.subid IS NULL OR NOT o.islake
  OR NOT EXISTS (SELECT 1 FROM fwapg.pcic_outlet_daily q WHERE q.subid = dv.subid);
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'diversions % are not PCIC lake outlets with a series', bad;
  END IF;

  SELECT string_agg(dv.subid::text, ', ') INTO bad
  FROM fwapg.pcic_diversions dv
  LEFT JOIN whse_basemapping.fwa_stream_networks_sp s ON s.linear_feature_id = dv.linear_feature_id
  WHERE s.linear_feature_id IS NULL
  OR s.edge_type IN (1425, 6010)
  OR s.localcode_ltree IS NULL
  OR s.wscode_ltree <@ '999'::ltree
  OR NOT EXISTS (
    SELECT 1 FROM whse_basemapping.fwa_streams_watersheds_lut l
    WHERE l.linear_feature_id = s.linear_feature_id
  );
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'diversions % have no usable exit: the waterbody is not on the blue line, or its lowest segment is unusable', bad;
  END IF;
END $$;

SELECT subid, blue_line_key, waterbody_key, linear_feature_id, downstream_route_measure, watershed_group_code,
  round(distance_to_stream) AS distance_to_stream
FROM fwapg.pcic_diversions;
