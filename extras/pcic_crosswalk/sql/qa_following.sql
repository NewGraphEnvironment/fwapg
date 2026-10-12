-- Line-following check at every placed outlet (NewGraphEnvironment/fwapg#8).
--
-- Does PCIC's river segment follow the FWA stream its outlet was placed on? The
-- drainage check (qa_drainage.sql) sees a stream of the wrong size; this one sees
-- a wrong stream of any size, by geometry alone. For each placed river outlet, the
-- part of its PCIC segment between 100 m and 1 km from the outlet (the first 100 m
-- runs through the confluence, where both branches are near) is compared with the
-- blue line of each of its candidates: the share of that part within 50 m of the
-- line. Lines are grouped by watershed_key, so a side channel and the main stem it
-- belongs to (pcic_crosswalk02_candidates.sql adds one for the other) count as one
-- river, and the placement's vote between them is not re-run here.
--
-- - 'follows_other': another river's line follows the segment better than the
--   placed river's, by more than 0.5 of the part's length
-- - 'follows_none': neither follows it (both under 0.2). The right stream may be
--   beyond the candidates (5 within 150 m), or the two networks differ there
-- - 'unmeasured': less than 100 m of segment to compare (short segments)
--
-- Lake outlets are not checked: a lake's outlet has no PCIC segment of its own.
-- Where PCIC gives a segment no flow direction (direction_method 'none', 217
-- placed outlets), the outlet end is arbitrary, and the part measured is the one
-- around the end that was placed.
--
-- Measured 2026-10-12 on the post-#14 build: of 37,293 placed river outlets,
-- 36,532 measured, 761 unmeasured; the placed river's share has a median of 1.0
-- and a 5th percentile of 0.91. The other-minus-placed gap is bimodal, with 30
-- outlets between +0.2 and +0.6, so the 0.5 margin sits in the gap: 248
-- 'follows_other', 186 'follows_none'. A 100 m buffer gives 246 and 132.
-- 179 of the 248 are in no other flag list (drainage, gauges). Seeded errors:
-- moving each outlet that passes onto another river's candidate flags 99.6% of
-- 12,848 seeds whose area is within 5 times the placed stream's (the drainage
-- check's blind spot) and 99.5% of 32,765 others; the Nicola main stem's outlet
-- 3008978 scores 1.0 on the Nicola and 0 on Clapperton Creek. Seeds only test the
-- case where the right line is a candidate and follows PCIC: the review in #8
-- measures the rest.
--
-- Builds fwapg.pcic_qa_following; run before the staging tables are dropped.

DROP TABLE IF EXISTS fwapg.pcic_qa_following;

CREATE TABLE fwapg.pcic_qa_following AS
WITH part AS (
  SELECT
    x.subid,
    x.watershed_group_code,
    x.blue_line_key,
    s.watershed_key,
    ST_Difference(
      ST_Intersection(r.geom, ST_Buffer(o.geom, 1000)),
      ST_Buffer(o.geom, 100)
    ) AS geom
  FROM whse_basemapping.pcic_fwa_crosswalk x
  INNER JOIN fwapg.pcic_outlets o ON o.subid = x.subid
  INNER JOIN fwapg.pcic_rivers r ON r.subid = x.subid
  INNER JOIN whse_basemapping.fwa_stream_networks_sp s ON s.linear_feature_id = x.linear_feature_id
  WHERE x.flag IS NULL
  AND NOT o.islake
),

-- share of the part within 50 m of each candidate's blue line; an outlet moved
-- below a junction (pcic_crosswalk06_subbasins.sql) stays on its candidate's line
shares AS (
  SELECT
    p.subid,
    c.blue_line_key,
    c.watershed_key,
    coalesce(ST_Length(ST_Intersection(p.geom, z.zone)), 0) / nullif(ST_Length(p.geom), 0) AS share
  FROM part p
  INNER JOIN (SELECT DISTINCT subid, blue_line_key, watershed_key FROM fwapg.pcic_candidates) c
    ON c.subid = p.subid
  CROSS JOIN LATERAL (
    SELECT ST_Union(ST_Buffer(s.geom, 50)) AS zone
    FROM whse_basemapping.fwa_stream_networks_sp s
    WHERE s.blue_line_key = c.blue_line_key
    AND ST_DWithin(s.geom, p.geom, 50)
  ) z
),

rivers AS (
  SELECT
    p.subid,
    p.watershed_group_code,
    p.blue_line_key,
    ST_Length(p.geom) AS part_m,
    max(sh.share) FILTER (WHERE sh.watershed_key = p.watershed_key) AS placed_share,
    coalesce(max(sh.share) FILTER (WHERE sh.watershed_key != p.watershed_key), 0) AS other_share,
    (array_agg(sh.blue_line_key ORDER BY sh.share DESC, sh.blue_line_key)
      FILTER (WHERE sh.watershed_key != p.watershed_key))[1] AS other_blue_line_key
  FROM part p
  LEFT JOIN shares sh ON sh.subid = p.subid
  GROUP BY p.subid, p.watershed_group_code, p.blue_line_key, p.geom
)

SELECT
  subid,
  watershed_group_code,
  blue_line_key,
  round(part_m::numeric, 1) AS part_m,
  round(placed_share::numeric, 3) AS placed_share,
  round(other_share::numeric, 3) AS other_share,
  other_blue_line_key,
  CASE
    -- no placed share: the placed river is missing from the candidates, which
    -- cannot happen by construction, so it is counted rather than passed
    WHEN part_m < 100 OR placed_share IS NULL THEN 'unmeasured'
    WHEN other_share > placed_share + 0.5 THEN 'follows_other'
    WHEN placed_share < 0.2 AND other_share < 0.2 THEN 'follows_none'
  END AS flag
FROM rivers;

ALTER TABLE fwapg.pcic_qa_following ADD PRIMARY KEY (subid);
ANALYZE fwapg.pcic_qa_following;

-- report
SELECT coalesce(flag, 'ok') AS following, count(*),
  count(*) FILTER (WHERE part_m >= 100 AND placed_share IS NULL) AS no_placed_share
FROM fwapg.pcic_qa_following
GROUP BY 1
ORDER BY 1;
