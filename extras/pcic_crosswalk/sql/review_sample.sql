-- Draw the sample for the visual review (NewGraphEnvironment/fwapg#8).
--
-- Strata, each drawn separately, at most :cap outlets (:cap_random for random):
--
-- - random: placed outlets. The only stratum the network's error rate comes from
-- - following: placed outlets the line-following check flags (qa_following.sql)
-- - rank_gt1: placed on a candidate other than the nearest
-- - unplaced: outlets with a candidate left unplaced (broken_chain, demoted)
-- - confluence: placed within 200 m, along its blue line, of a junction of
--   comparable streams (the tributary's stream order at least the main stem's):
--   a tributary joining the line it is on, or its own line's mouth. Any junction
--   would take 74% of placements: PCIC outlets sit at confluences
-- - flagged: the other automatic flags: drainage small or big (qa_drainage.sql),
--   over 10 times PCIC's flow, or the PCIC outlet at a gauge where FWA and PCIC
--   flow disagree (qa_gauges.sh)
--
-- The draw is an md5 order of (stratum, subid, seed) in the C collation, so it
-- depends on the build and the seed and nothing else (not on a plan's row order,
-- as random() would). An outlet drawn by several strata is reviewed once and
-- counts toward each that drew it. Every stratum a drawn outlet belongs to is
-- listed too, with drawn = false where that stratum did not draw it.
--
-- review_id is a second md5 order over the drawn outlets: it is also the working
-- order, and says nothing about why an outlet was drawn.
--
-- Needs the tables the job keeps: pcic_qa_outlets, pcic_qa_following,
-- pcic_qa_drainage, pcic_qa_flow, pcic_qa_gauges and blk_paths.

DROP TABLE IF EXISTS fwapg.pcic_review_strata;
CREATE TABLE fwapg.pcic_review_strata AS
WITH placed AS (
  SELECT x.*, s.stream_order
  FROM whse_basemapping.pcic_fwa_crosswalk x
  INNER JOIN whse_basemapping.fwa_stream_networks_sp s ON s.linear_feature_id = x.linear_feature_id
  WHERE x.flag IS NULL
),
junctions AS (
  -- where each line joins its parent, and the tributary's order
  SELECT
    p.blue_line_key AS trib,
    p.path_blks[1] AS parent,
    p.path_measures[1] AS measure,
    (SELECT max(t.stream_order) FROM whse_basemapping.fwa_stream_networks_sp t
     WHERE t.blue_line_key = p.blue_line_key) AS trib_order
  FROM fwapg.blk_paths p
  WHERE cardinality(p.path_blks) > 0
),
confluence AS (
  -- a comparable tributary joins the placed line within 200 m
  SELECT x.subid
  FROM placed x
  INNER JOIN junctions j ON j.parent = x.blue_line_key
  WHERE abs(j.measure - x.downstream_route_measure) <= 200
  AND j.trib_order >= x.stream_order
  UNION
  -- the placed line's own mouth is within 200 m, on a parent of no higher order
  -- at the junction
  SELECT x.subid
  FROM placed x
  INNER JOIN junctions j ON j.trib = x.blue_line_key
  INNER JOIN whse_basemapping.fwa_stream_networks_sp ps
    ON ps.blue_line_key = j.parent
    AND j.measure >= ps.downstream_route_measure AND j.measure < ps.upstream_route_measure
  WHERE x.downstream_route_measure <= 200
  AND x.stream_order >= ps.stream_order
)
SELECT subid, 'random' AS stratum FROM placed
UNION ALL
SELECT subid, 'following' FROM fwapg.pcic_qa_following WHERE flag IN ('follows_other', 'follows_none')
UNION ALL
SELECT subid, 'rank_gt1' FROM placed WHERE candidate_rank > 1
UNION ALL
SELECT subid, 'unplaced' FROM whse_basemapping.pcic_fwa_crosswalk WHERE flag IN ('broken_chain', 'demoted')
UNION ALL
SELECT subid, 'confluence' FROM confluence
UNION ALL
SELECT subid, 'flagged' FROM (
  SELECT subid FROM fwapg.pcic_qa_drainage WHERE flag IN ('small', 'big')
  UNION
  SELECT subid FROM fwapg.pcic_qa_flow WHERE q_fwa > 10 * q_pcic AND q_fwa > 1
  UNION
  SELECT pcic_subid FROM fwapg.pcic_qa_gauges
  WHERE fwa_over_pcic NOT BETWEEN 0.9 AND 1.1 AND NOT any_pcic_matches_fwa
) f
WHERE subid IS NOT NULL;

DROP TABLE IF EXISTS fwapg.pcic_review_design;
CREATE TABLE fwapg.pcic_review_design AS
WITH drawn AS (
  SELECT subid, stratum
  FROM (
    SELECT subid, stratum,
      row_number() OVER (PARTITION BY stratum
        ORDER BY md5(stratum || '|' || subid || '|' || :'seed') COLLATE "C") AS n
    FROM fwapg.pcic_review_strata
  ) r
  WHERE n <= CASE WHEN stratum = 'random' THEN :cap_random ELSE :cap END
),
ids AS (
  SELECT subid, row_number() OVER (ORDER BY md5('review|' || subid || '|' || :'seed') COLLATE "C") AS review_id
  FROM (SELECT DISTINCT subid FROM drawn) d
)
SELECT i.review_id::integer, i.subid, s.stratum, d.subid IS NOT NULL AS drawn
FROM ids i
INNER JOIN fwapg.pcic_review_strata s ON s.subid = i.subid
LEFT JOIN drawn d ON d.subid = s.subid AND d.stratum = s.stratum;

-- population and draw per stratum, for review_build.sh's checks and the README
SELECT s.stratum, count(*) AS population,
  (SELECT count(*) FROM fwapg.pcic_review_design d WHERE d.stratum = s.stratum AND d.drawn) AS drawn
FROM fwapg.pcic_review_strata s
GROUP BY s.stratum
ORDER BY s.stratum != 'random', s.stratum;
