-- Per WSC gauge: observed, PCIC and FWA mean annual flow (means of the monthly
-- climatologies, over months the gauge observed in at least 10 years), and the
-- drainage areas. See qa_gauges.sh.

CREATE INDEX IF NOT EXISTS pcic_qa_rivers_geom_idx ON fwapg.pcic_qa_rivers USING gist (geom);
CREATE INDEX IF NOT EXISTS pcic_qa_outlet_monthly_idx ON fwapg.pcic_qa_outlet_monthly (subid, month);
ANALYZE fwapg.pcic_qa_rivers;

DROP TABLE IF EXISTS fwapg.pcic_qa_gauges;

CREATE TABLE fwapg.pcic_qa_gauges AS
WITH obs AS (
  -- observed monthly climatology, months with >= 10 years only
  SELECT station, month, avg(q_m3s) AS q_obs
  FROM fwapg.pcic_qa_wsc_monthly
  GROUP BY station, month
  HAVING count(*) >= 10
),
stations AS (
  SELECT s.*, ST_Transform(ST_SetSRID(ST_MakePoint(s.lon, s.lat), 4326), 3005) AS geom
  FROM fwapg.pcic_qa_stations s
  WHERE s.area_km2 > 0
  AND (SELECT count(*) FROM obs o WHERE o.station = s.station) = 12
),
-- FWA: of the streams within 500 m, the one whose upstream area is closest to the
-- gauge's drainage area; among those within 10% of it, a main stem before a side
-- channel (the watershed lookup gives a side channel its main stem's area, but a
-- side channel carries only local runoff)
fwa AS (
  SELECT DISTINCT ON (s.station)
    s.station,
    c.linear_feature_id,
    c.gnis_name,
    c.distance_to_stream AS fwa_snap_m,
    ua.upstream_area_ha / 100 AS fwa_area_km2
  FROM stations s
  CROSS JOIN LATERAL whse_basemapping.FWA_IndexPoint(s.geom, 500, 5) c
  INNER JOIN whse_basemapping.fwa_stream_networks_sp sp ON c.linear_feature_id = sp.linear_feature_id
  INNER JOIN whse_basemapping.fwa_streams_watersheds_lut l ON c.linear_feature_id = l.linear_feature_id
  INNER JOIN whse_basemapping.fwa_watersheds_upstream_area ua ON l.watershed_feature_id = ua.watershed_feature_id
  ORDER BY s.station,
    abs(ln(greatest(ua.upstream_area_ha, 1) / 100 / s.area_km2)) > ln(1.1),
    sp.blue_line_key != sp.watershed_key,
    abs(ln(greatest(ua.upstream_area_ha, 1) / 100 / s.area_km2)),
    c.distance_to_stream
),
-- PCIC: the nearest PCIC river segment within 500 m, on PCIC's own network (no
-- crosswalk involved)
pcic AS (
  SELECT DISTINCT ON (s.station)
    s.station,
    r.subid,
    ST_Distance(r.geom, s.geom) AS pcic_snap_m
  FROM stations s
  INNER JOIN fwapg.pcic_qa_rivers r ON ST_DWithin(r.geom, s.geom, 500)
  ORDER BY s.station, ST_Distance(r.geom, s.geom)
),
-- gauges sit at confluences, where the nearest PCIC segment can be the other
-- branch: note whether ANY PCIC segment within 500 m matches the FWA flow within
-- 10%, so a disagreement with the nearest one can be told apart from a crosswalk
-- error
pcic_annual AS (
  SELECT subid, avg(q_m3s) AS q FROM fwapg.pcic_qa_outlet_monthly GROUP BY subid
),
fwa_annual AS (
  SELECT f.station, avg(d.q_m3s) AS q
  FROM fwa f
  INNER JOIN whse_basemapping.fwa_stream_networks_discharge_monthly d ON d.linear_feature_id = f.linear_feature_id
  GROUP BY f.station
),
pcic_any AS (
  SELECT s.station, bool_or(abs(pa.q / nullif(fa.q, 0) - 1) <= 0.1) AS any_pcic_matches_fwa
  FROM stations s
  INNER JOIN fwapg.pcic_qa_rivers r ON ST_DWithin(r.geom, s.geom, 500)
  INNER JOIN pcic_annual pa ON pa.subid = r.subid
  INNER JOIN fwa_annual fa ON fa.station = s.station
  GROUP BY s.station
)
SELECT
  s.station,
  s.name,
  s.area_km2 AS gauge_area_km2,
  f.gnis_name AS fwa_stream,
  round(f.fwa_snap_m::numeric, 1) AS fwa_snap_m,
  round(f.fwa_area_km2::numeric, 1) AS fwa_area_km2,
  p.subid AS pcic_subid,
  round(p.pcic_snap_m::numeric, 1) AS pcic_snap_m,
  x.flag AS pcic_crosswalk_flag,
  coalesce(pa.any_pcic_matches_fwa, false) AS any_pcic_matches_fwa,
  round(avg(o.q_obs)::numeric, 3) AS q_obs,
  round(avg(q.q_m3s)::numeric, 3) AS q_pcic,
  round(avg(d.q_m3s)::numeric, 3) AS q_fwa,
  round((avg(d.q_m3s) / nullif(avg(q.q_m3s), 0))::numeric, 3) AS fwa_over_pcic,
  round((avg(q.q_m3s) / nullif(avg(o.q_obs), 0))::numeric, 3) AS pcic_over_obs,
  round((f.fwa_area_km2 / s.area_km2)::numeric, 3) AS fwa_area_over_gauge
FROM stations s
INNER JOIN obs o ON o.station = s.station
LEFT JOIN fwa f ON f.station = s.station
LEFT JOIN pcic p ON p.station = s.station
LEFT JOIN whse_basemapping.pcic_fwa_crosswalk x ON x.subid = p.subid
LEFT JOIN pcic_any pa ON pa.station = s.station
LEFT JOIN fwapg.pcic_qa_outlet_monthly q ON q.subid = p.subid AND q.month = o.month
LEFT JOIN whse_basemapping.fwa_stream_networks_discharge_monthly d
  ON d.linear_feature_id = f.linear_feature_id AND d.month = o.month
GROUP BY s.station, s.name, s.area_km2, f.gnis_name, f.fwa_snap_m, f.fwa_area_km2, p.subid, p.pcic_snap_m, x.flag, pa.any_pcic_matches_fwa;
