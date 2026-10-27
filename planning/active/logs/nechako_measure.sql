-- #24: the Nechako Reservoir case, measured on the pcic.* tables of one build.
-- Run before and after the change: psql $DATABASE_URL -v period=1951-2012 -f nechako_measure.sql
\pset footer off
\echo == crosswalk
SELECT crosswalk_md5, period FROM pcic.runs WHERE (model, scenario, period) = ('PNWNAmet', 'historical', :'period');

\echo == outlets per group (PCIC outlet point in the group), placed and flags
SELECT g.watershed_group_code AS wsg, count(*) AS outlets, count(x.linear_feature_id) AS placed,
  count(*) FILTER (WHERE x.flag = 'broken_chain') AS broken_chain,
  count(*) FILTER (WHERE x.flag = 'no_candidate') AS no_candidate,
  count(*) FILTER (WHERE x.flag = 'demoted') AS demoted
FROM pcic.fwa_crosswalk x
INNER JOIN whse_basemapping.fwa_watershed_groups_poly g ON ST_Intersects(g.geom, (SELECT o.geom FROM fwapg.pcic_qa_outlets o WHERE o.subid = x.subid))
WHERE g.watershed_group_code IN ('LEUT', 'UEUT', 'UNRS', 'LNRS', 'CHES')
GROUP BY 1 ORDER BY 1;

\echo == mean annual flow per segment, per group: specific runoff (mm/yr over FWA upstream area)
WITH q AS (
  SELECT d.linear_feature_id, d.watershed_group_code, avg(d.q_m3s) AS q
  FROM pcic.discharge_monthly d
  WHERE (d.model, d.scenario, d.period) = ('PNWNAmet', 'historical', :'period')
  AND d.watershed_group_code IN ('LEUT', 'UEUT', 'UNRS', 'LNRS', 'CHES')
  GROUP BY 1, 2
), r AS (
  SELECT q.*, q.q / (ua.upstream_area_ha / 100) * 31536 AS mm
  FROM q
  INNER JOIN whse_basemapping.fwa_streams_watersheds_lut l ON l.linear_feature_id = q.linear_feature_id
  INNER JOIN whse_basemapping.fwa_watersheds_upstream_area ua ON ua.watershed_feature_id = l.watershed_feature_id
  WHERE ua.upstream_area_ha > 0
)
SELECT watershed_group_code AS wsg, count(*) AS segments,
  round(percentile_cont(0.5) WITHIN GROUP (ORDER BY mm)::numeric, 1) AS median_mm,
  count(*) FILTER (WHERE mm < 5) AS under_5mm,
  round(100.0 * count(*) FILTER (WHERE mm < 5) / count(*), 1) AS pct_under_5mm
FROM r GROUP BY 1 ORDER BY 1;

\echo == key points: mean annual flow (m3/s)
WITH pts(label, blue_line_key, measure) AS (
  VALUES
    ('Whitesail Lake, top of the reservoir line', 356362759, 503000::float8),
    ('Ootsa Lake', 356362759, 400000),
    ('Natalkuz Lake', 356362759, 330000),
    ('Knewstubb Lake, mid', 356362759, 300000),
    ('Knewstubb Lake, exit segment', 356362759, 288852.5),
    ('Nechako canyon below Kenney Dam', 356362759, 288500),
    ('Nechako above the Cheslatta', 356362759, 280500),
    ('Nechako below the Cheslatta', 356362759, 280000),
    ('Skins Lake spillway line, top', 356209076, 1860),
    ('Cheslatta River near its mouth', 356358538, 100)
), seg AS (
  SELECT p.label, s.linear_feature_id, s.watershed_group_code
  FROM pts p
  CROSS JOIN LATERAL (
    SELECT s.* FROM whse_basemapping.fwa_stream_networks_sp s
    WHERE s.blue_line_key = p.blue_line_key AND s.downstream_route_measure <= p.measure
    ORDER BY s.downstream_route_measure DESC LIMIT 1
  ) s
)
SELECT seg.label, seg.linear_feature_id, seg.watershed_group_code AS wsg, w.subid,
  round(avg(d.q_m3s)::numeric, 3) AS q_annual
FROM seg
LEFT JOIN pcic.segment_weights w ON w.linear_feature_id = seg.linear_feature_id
LEFT JOIN pcic.discharge_monthly d ON d.linear_feature_id = seg.linear_feature_id
  AND (d.model, d.scenario, d.period) = ('PNWNAmet', 'historical', :'period')
GROUP BY 1, 2, 3, 4 ORDER BY min(seg.label) = seg.label, 1;

\echo == outlets of the diversion
SELECT x.subid, x.flag, x.blue_line_key, round(x.downstream_route_measure::numeric, 1) AS measure, x.fwa_parent_subid, x.anchor_subid
FROM pcic.fwa_crosswalk x WHERE x.subid IN (1007550, 1008709, 1002307) ORDER BY 1;
