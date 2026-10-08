-- Build one outlet point per PCIC sub-basin (river segments and lakes), plus each
-- sub-basin's root (terminal outlet of its tree) and depth (steps to the root).
--
-- PCIC river segments carry no flow direction. The outlet is the segment end that
-- touches the downstream feature (dowsubid); where there is no downstream feature it
-- is the end farthest from the upstream features. A lake's outlet is the upstream end
-- of the river segment that drains it.
--
-- Outlets sit at confluences, where the nearest FWA stream is as often the other
-- branch as the one the segment follows. Snapping uses probe_geom instead: a point
-- up to 100 m (at most a quarter of the segment) back up the segment from its outlet.

CREATE INDEX IF NOT EXISTS pcic_rivers_subid_idx ON fwapg.pcic_rivers (subid);
CREATE INDEX IF NOT EXISTS pcic_rivers_dowsubid_idx ON fwapg.pcic_rivers (dowsubid);
CREATE INDEX IF NOT EXISTS pcic_lakes_subid_idx ON fwapg.pcic_lakes (subid);
ANALYZE fwapg.pcic_rivers;
ANALYZE fwapg.pcic_lakes;

DROP TABLE IF EXISTS fwapg.pcic_outlets;

CREATE TABLE fwapg.pcic_outlets AS

WITH features AS (
  SELECT subid, dowsubid, false AS islake, geom FROM fwapg.pcic_rivers
  UNION ALL
  SELECT subid, dowsubid, true AS islake, geom FROM fwapg.pcic_lakes
),

-- segment end points; a multipart segment that does not merge runs from the
-- start of its first part to the end of its last part
ends AS (
  SELECT
    subid,
    m,
    CASE WHEN GeometryType(m) = 'LINESTRING' THEN ST_StartPoint(m)
      ELSE ST_StartPoint(ST_GeometryN(m, 1)) END AS p0,
    CASE WHEN GeometryType(m) = 'LINESTRING' THEN ST_EndPoint(m)
      ELSE ST_EndPoint(ST_GeometryN(m, ST_NumGeometries(m))) END AS p1
  FROM (SELECT subid, ST_LineMerge(geom) AS m FROM fwapg.pcic_rivers) r
),

river_directions AS (
  SELECT
    r.subid,
    r.dowsubid,
    e.m,
    e.p0,
    e.p1,
    CASE
      WHEN d.geom IS NOT NULL THEN ST_Distance(e.p1, d.geom) <= ST_Distance(e.p0, d.geom)
      WHEN u.geom IS NOT NULL THEN ST_Distance(e.p1, u.geom) >= ST_Distance(e.p0, u.geom)
      ELSE true
    END AS outlet_at_end,
    CASE
      WHEN d.geom IS NOT NULL THEN 'downstream'
      WHEN u.geom IS NOT NULL THEN 'upstream'
      ELSE 'none'
    END AS direction_method,
    -- distance from the chosen outlet to the downstream feature; should be ~0
    CASE WHEN d.geom IS NOT NULL THEN
      round(least(ST_Distance(e.p0, d.geom), ST_Distance(e.p1, d.geom))::numeric, 1)
    END AS gap_to_downstream_m
  FROM fwapg.pcic_rivers r
  INNER JOIN ends e ON r.subid = e.subid
  LEFT JOIN features d ON r.dowsubid = d.subid
  LEFT JOIN LATERAL (
    SELECT ST_Collect(f.geom) AS geom
    FROM features f
    WHERE f.dowsubid = r.subid
  ) u ON true
),

river_outlets AS (
  SELECT
    subid,
    dowsubid,
    false AS islake,
    CASE WHEN outlet_at_end THEN p1 ELSE p0 END AS geom,
    CASE
      WHEN GeometryType(m) = 'LINESTRING' AND ST_Length(m) > 0 THEN
        ST_LineInterpolatePoint(m,
          CASE WHEN outlet_at_end
            THEN 1 - least(100, ST_Length(m) / 4) / ST_Length(m)
            ELSE least(100, ST_Length(m) / 4) / ST_Length(m)
          END)
      ELSE CASE WHEN outlet_at_end THEN p1 ELSE p0 END
    END AS probe_geom,
    direction_method,
    gap_to_downstream_m
  FROM river_directions
),

-- a lake drains through the river segment(s) whose dowsubid is downstream of the
-- lake; the lake's outlet is that river's end nearest the lake
lake_outlets AS (
  SELECT
    l.subid,
    l.dowsubid,
    true AS islake,
    coalesce(
      CASE WHEN ST_Distance(e.p0, l.geom) <= ST_Distance(e.p1, l.geom) THEN e.p0 ELSE e.p1 END,
      ST_PointOnSurface(l.geom)
    ) AS geom,
    coalesce(
      CASE WHEN ST_Distance(e.p0, l.geom) <= ST_Distance(e.p1, l.geom) THEN e.p0 ELSE e.p1 END,
      ST_PointOnSurface(l.geom)
    ) AS probe_geom,
    CASE WHEN e.subid IS NOT NULL THEN 'lake_downstream_river' ELSE 'lake_point_on_surface' END AS direction_method,
    NULL::numeric AS gap_to_downstream_m
  FROM fwapg.pcic_lakes l
  LEFT JOIN ends e ON l.dowsubid = e.subid
)

SELECT * FROM river_outlets
UNION ALL
SELECT * FROM lake_outlets;

ALTER TABLE fwapg.pcic_outlets ADD PRIMARY KEY (subid);
ALTER TABLE fwapg.pcic_outlets ADD COLUMN root_subid integer;
ALTER TABLE fwapg.pcic_outlets ADD COLUMN depth integer;
CREATE INDEX ON fwapg.pcic_outlets (dowsubid);
CREATE INDEX ON fwapg.pcic_outlets USING gist (geom);

-- root and depth: walk up from each terminal outlet (dowsubid not in the network)
WITH RECURSIVE walk AS (
  SELECT o.subid, o.subid AS root_subid, 0 AS depth
  FROM fwapg.pcic_outlets o
  WHERE NOT EXISTS (SELECT 1 FROM fwapg.pcic_outlets d WHERE d.subid = o.dowsubid)
  UNION ALL
  SELECT o.subid, w.root_subid, w.depth + 1
  FROM fwapg.pcic_outlets o
  INNER JOIN walk w ON o.dowsubid = w.subid
)
UPDATE fwapg.pcic_outlets o
SET root_subid = w.root_subid, depth = w.depth
FROM walk w
WHERE o.subid = w.subid;

ANALYZE fwapg.pcic_outlets;
