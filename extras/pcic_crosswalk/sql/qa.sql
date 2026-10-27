-- QA tests for the PCIC crosswalk, all should return result = t. Run before the
-- staging tables are dropped; pcic_crosswalk.sh stops before export if any is f.
-- Reports are in qa_report.sql.

-- the segment an outlet is placed on carries the outlet's accumulated flow. Where
-- several outlets share a segment it belongs to the uppermost (as in
-- pcic_crosswalk07_segments.sql), so only that one is checked
WITH placed AS (
  SELECT DISTINCT ON (x.linear_feature_id) x.subid, x.linear_feature_id
  FROM fwapg.pcic_fwa_crosswalk x
  WHERE x.flag IS NULL
  ORDER BY x.linear_feature_id, x.downstream_route_measure DESC, x.depth DESC, x.subid DESC
)
SELECT 'outlet segments carry accumulated flow' AS test,
  bool_and(abs(d.q_m3s - greatest(m.q_acc, 0)) <= 0.001) AS result
FROM placed p
INNER JOIN fwapg.pcic_subbasins_monthly m ON m.subid = p.subid
INNER JOIN fwapg.pcic_discharge_monthly d
  ON d.linear_feature_id = p.linear_feature_id AND d.month = m.month;

-- flow accumulated on the FWA matches PCIC's outflow (mean annual, within 5%) at
-- most placed outlets, and at nearly all large ones. Where it does not, PCIC's
-- network and the FWA join streams in different places.
WITH annual AS (
  SELECT m.subid, avg(m.q_acc) AS q_acc, avg(q.q_m3s) AS q_pcic
  FROM fwapg.pcic_subbasins_monthly m
  INNER JOIN fwapg.pcic_outlet_monthly q ON q.subid = m.subid AND q.month = m.month
  GROUP BY m.subid
)
SELECT 'accumulated flow within 5% of PCIC at >= 90% of placed outlets' AS test,
  avg((abs(q_acc - q_pcic) <= 0.05 * q_pcic + 0.01)::int) >= 0.9 AS result
FROM annual
UNION ALL
SELECT 'accumulated flow within 5% of PCIC at >= 95% of placed outlets over 100 m3/s',
  avg((abs(q_acc - q_pcic) <= 0.05 * q_pcic)::int) >= 0.95
FROM annual
WHERE q_pcic > 100;

-- most outlets with an FWA candidate are placed
SELECT 'placed >= 90% of outlets with a candidate' AS test,
  count(*) FILTER (WHERE flag IS NULL)::numeric / count(*) FILTER (WHERE flag IS DISTINCT FROM 'no_candidate') >= 0.9 AS result
FROM fwapg.pcic_fwa_crosswalk;

-- every output segment has twelve months and no negative flow
SELECT 'twelve months per segment' AS test, bool_and(n = 12) AS result
FROM (SELECT count(*) AS n FROM fwapg.pcic_discharge_monthly GROUP BY linear_feature_id) s;

SELECT 'no negative flow' AS test, NOT EXISTS (
  SELECT 1 FROM fwapg.pcic_discharge_monthly WHERE q_m3s < 0
) AS result;

-- mean annual flow rarely drops by more than 10% from one segment to the next
-- going down any blue line, main stem or side channel (where it is over 10 m3/s).
-- Measured at 10 of 89,251 pairs (0.01%); the ceiling is 0.1%. Misplaced outlets
-- and position comparisons that misread local codes showed as hundreds. Since the
-- Nechako Reservoir was listed as a diversion (NewGraphEnvironment/fwapg#24),
-- Kenney Dam is one more: its water leaves by the spillway, not the canyon.
WITH annual AS (
  SELECT s.blue_line_key, s.downstream_route_measure, avg(d.q_m3s) AS q
  FROM whse_basemapping.fwa_stream_networks_sp s
  INNER JOIN fwapg.pcic_discharge_monthly d ON s.linear_feature_id = d.linear_feature_id
  GROUP BY s.blue_line_key, s.downstream_route_measure
),
pairs AS (
  SELECT q, lead(q) OVER (PARTITION BY blue_line_key ORDER BY downstream_route_measure DESC) AS q_down
  FROM annual
)
SELECT 'flow drops > 10% downstream on <= 0.1% of segment pairs over 10 m3/s' AS test,
  count(*) > 0 AND avg((q_down < q * 0.9)::int) <= 0.001 AS result
FROM pairs
WHERE q_down IS NOT NULL
AND q > 10;

-- placements that put a tributary's outlet on the river it joins carry many times
-- PCIC's flow. Measured: about 24 before side channels were handled, 358 when
-- side-channel candidates were moved to the main stem outright, 85 with the
-- current handling (17 on an added main-stem point; most of the rest are PCIC
-- siblings one above the other on the FWA, listed in qa_report.sql for review
-- in NewGraphEnvironment/fwapg#8). The ceiling guards against the 358 class.
WITH annual AS (
  SELECT m.subid, avg(m.q_acc) AS q_acc, avg(q.q_m3s) AS q_pcic
  FROM fwapg.pcic_subbasins_monthly m
  INNER JOIN fwapg.pcic_outlet_monthly q ON q.subid = m.subid AND q.month = m.month
  GROUP BY m.subid
)
SELECT 'at most 100 placed outlets carry more than 10 times PCIC''s flow' AS test,
  count(*) FILTER (WHERE q_acc > 10 * q_pcic AND q_acc > 1) <= 100 AND count(*) > 0 AS result
FROM annual;

-- a tributary entering the Skeena through a braid (code-check round 7)
WITH annual AS (
  SELECT m.subid, avg(m.q_acc) AS q_acc, avg(q.q_m3s) AS q_pcic
  FROM fwapg.pcic_subbasins_monthly m
  INNER JOIN fwapg.pcic_outlet_monthly q ON q.subid = m.subid AND q.month = m.month
  WHERE m.subid = 8007998
  GROUP BY m.subid
)
SELECT 'Kitsumkalum outlet 8007998 is placed and within 5% of PCIC' AS test,
  coalesce(bool_and(abs(q_acc - q_pcic) <= 0.05 * q_pcic), false) AS result
FROM annual;

-- a tributary's water enters at the junction, the start of the main-stem segment
-- above it (FWA measures run [downstream, upstream)), so an outlet on that vertex
-- whose PCIC descendant joins there (a child, or one anchored to it through
-- unplaced children) is above the confluence its flow includes.
-- pcic_crosswalk06_subbasins.sql moves it to the segment below (NewGraphEnvironment/fwapg#14;
-- 6 outlets in the 2026-10 build). Line mouths are included: there is no segment
-- below to move to, and the step > 0 rules of 06 and 07 would parent the
-- descendant below the outlet, so such a case has to be looked at. So is an outlet
-- left on its vertex because another placed outlet is stacked on it. Vertex and
-- junction are compared within 1 mm: a measure interpolated along a segment can
-- differ from the segment start it names by float noise
SELECT 'no placed outlet sits above a confluence its PCIC child joins at' AS test, NOT EXISTS (
  SELECT 1
  FROM fwapg.pcic_fwa_crosswalk x
  INNER JOIN whse_basemapping.fwa_stream_networks_sp s ON s.linear_feature_id = x.linear_feature_id
  INNER JOIN fwapg.pcic_fwa_crosswalk c
    ON c.anchor_subid = x.subid AND c.flag IS NULL AND c.blue_line_key != x.blue_line_key
  INNER JOIN fwapg.blk_paths bp ON bp.blue_line_key = c.blue_line_key
  CROSS JOIN LATERAL unnest(bp.path_blks, bp.path_measures) AS u(blk, measure)
  WHERE x.flag IS NULL
  AND abs(x.downstream_route_measure - s.downstream_route_measure) < 0.001
  AND u.blk = x.blue_line_key
  AND abs(u.measure - x.downstream_route_measure) < 0.001
) AS result;

-- an outlet on the segment below a junction, but a hair above the junction's
-- measure, still receives the tributary: blue line 356567538 (2,130 ha) joins
-- 356369704 1e-14 m below outlet 5012573 and carried no flow in any month before
-- NewGraphEnvironment/fwapg#14
SELECT 'tributary 356567538 carries flow' AS test,
  coalesce(min(m.q) > 0, false) AS result
FROM (
  SELECT max(d.q_m3s) AS q
  FROM whse_basemapping.fwa_stream_networks_sp s
  INNER JOIN fwapg.pcic_discharge_monthly d ON d.linear_feature_id = s.linear_feature_id
  WHERE s.blue_line_key = 356567538
) m;

-- every placed outlet whose FWA parent is on another blue line joins the parent's
-- line at least 1 mm above the start of the parent's segment, line mouths
-- included: otherwise the parent's own segment would not carry the child's flow
-- (pcic_crosswalk07_segments.sql passes a segment only above its start). This holds
-- by construction while the step > 0 rules of 06 and 07 agree, and guards them
-- against drifting apart. The 6 outlets of the 2026-10 build that sat on their
-- child's junction failed it
WITH pairs AS (
  SELECT EXISTS (
    SELECT 1
    FROM fwapg.blk_paths bp, unnest(bp.path_blks, bp.path_measures) AS u(blk, measure)
    WHERE bp.blue_line_key = c.blue_line_key
    AND u.blk = p.blue_line_key
    AND u.measure >= s.downstream_route_measure + 0.001
  ) AS ok
  FROM fwapg.pcic_fwa_crosswalk c
  INNER JOIN fwapg.pcic_fwa_crosswalk p ON p.subid = c.fwa_parent_subid
  INNER JOIN whse_basemapping.fwa_stream_networks_sp s ON s.linear_feature_id = p.linear_feature_id
  WHERE c.flag IS NULL
  AND c.blue_line_key != p.blue_line_key
  -- a diversion's parent is where PCIC sends its water, not on its path (tested below)
  AND NOT EXISTS (SELECT 1 FROM fwapg.pcic_diversions dv WHERE dv.subid = c.subid)
)
SELECT 'every FWA child on another blue line joins above the start of its parent''s segment' AS test,
  count(*) > 0 AND bool_and(ok) AS result
FROM pairs;

-- flow steps up at the junction itself, not on the segment above it: blue line
-- 356362488 is joined by 356359224 at the start of segment 701317184, so 701317184
-- carries the main stem's flow above (14 m3/s in June) and 701317270 below it the
-- sum (695 m3/s). Before NewGraphEnvironment/fwapg#14, 701317184 carried 685
SELECT 'tributary 356359224 steps up flow below its junction, not above it' AS test,
  coalesce(bool_and(a.q_m3s < 0.5 * b.q_m3s), false) AS result
FROM fwapg.pcic_discharge_monthly a
INNER JOIN fwapg.pcic_discharge_monthly b ON b.month = a.month
WHERE a.linear_feature_id = 701317184
AND b.linear_feature_id = 701317270
AND a.month = 6;

-- the same across the network: at junctions within 1 mm of a segment start whose
-- joining line carries more than 1 m3/s in June, the step in June flow rarely
-- lands on the segment above the junction (its flow minus the next segment up's is
-- more than half the joining line's). Measured 2,373 of 18,942 before
-- NewGraphEnvironment/fwapg#14 and 678 after: about half of those have an outlet
-- higher on that segment whose PCIC flow includes the tributary (an unplaced PCIC
-- child anchored to it), and the rest are area shares where the watershed lookup
-- gives the segment the tributary's area. The ceiling guards against the 2,373 class
WITH junctions AS (
  SELECT
    (SELECT t.linear_feature_id FROM whse_basemapping.fwa_stream_networks_sp t
     WHERE t.blue_line_key = bp.blue_line_key ORDER BY t.downstream_route_measure LIMIT 1) AS trib_lfid,
    u.linear_feature_id AS upper_lfid,
    (SELECT a.linear_feature_id FROM whse_basemapping.fwa_stream_networks_sp a
     WHERE a.blue_line_key = u.blue_line_key AND a.downstream_route_measure > u.downstream_route_measure + 0.001
     ORDER BY a.downstream_route_measure LIMIT 1) AS above_lfid
  FROM fwapg.blk_paths bp
  INNER JOIN whse_basemapping.fwa_stream_networks_sp u
    ON u.blue_line_key = bp.path_blks[1]
    AND abs(u.downstream_route_measure - bp.path_measures[1]) < 0.001
  WHERE cardinality(bp.path_blks) > 0
)
SELECT 'flow steps up on the segment above the junction at <= 1,000 junctions over 1 m3/s' AS test,
  count(*) > 10000 AND count(*) FILTER (WHERE qu.q_m3s - qa.q_m3s > 0.5 * qt.q_m3s) <= 1000 AS result
FROM junctions j
INNER JOIN fwapg.pcic_discharge_monthly qt ON qt.linear_feature_id = j.trib_lfid AND qt.month = 6
INNER JOIN fwapg.pcic_discharge_monthly qu ON qu.linear_feature_id = j.upper_lfid AND qu.month = 6
INNER JOIN fwapg.pcic_discharge_monthly qa ON qa.linear_feature_id = j.above_lfid AND qa.month = 6
WHERE qt.q_m3s > 1;

-- drainage size at every placed outlet (qa_drainage.sql, NewGraphEnvironment/fwapg#7):
-- outlets on a main stem whose PCIC drainage (river length and flow) is far from
-- the FWA area they sit on. Measured 218 'small' and 126 'big' of 37,040; the
-- ceilings catch a class of misplacement (seeding 200 small outlets onto streams
-- with 10 times the area takes 'small' past 400), not each one, which #8 reviews.
-- An outlet with no FWA area or median is 'unmeasured' and fails the test, so a
-- missing or partly loaded area table cannot pass as "nothing flagged"
SELECT 'at most 300 main-stem outlets flagged small and 200 big by the drainage check, none unmeasured' AS test,
  count(*) FILTER (WHERE main_stem) > 0
  AND count(*) FILTER (WHERE flag = 'unmeasured') = 0
  AND count(*) FILTER (WHERE flag = 'small') <= 300
  AND count(*) FILTER (WHERE flag = 'big') <= 200 AS result
FROM fwapg.pcic_qa_drainage;


-- line-following at every placed river outlet (qa_following.sql,
-- NewGraphEnvironment/fwapg#8): outlets whose PCIC segment follows another
-- river's FWA line, or none. Measured 248 'follows_other' and 186 'follows_none'
-- of 36,532 measured; seeding outlets onto another river's candidate flags 99.6%,
-- so a class of misplacement takes 'follows_other' far past its ceiling. An outlet
-- with enough segment to measure but no share on its own placed river means the
-- check is broken, and fails the test
SELECT 'at most 400 placed outlets follow another river and 300 none, every measured outlet has a placed share' AS test,
  count(*) FILTER (WHERE flag IS DISTINCT FROM 'unmeasured') > 10000
  AND count(*) FILTER (WHERE part_m >= 100 AND placed_share IS NULL) = 0
  AND count(*) FILTER (WHERE flag = 'follows_other') <= 400
  AND count(*) FILTER (WHERE flag = 'follows_none') <= 300 AS result
FROM fwapg.pcic_qa_following;

-- diversions (pcic_crosswalk03_diversions.sql, NewGraphEnvironment/fwapg#24): a
-- listed outlet is placed at its listed FWA exit, its position parent is recorded,
-- and its FWA parent is its nearest placed PCIC ancestor, where PCIC sends its water
SELECT 'every diversion is placed at its exit, with its position and flow parents' AS test,
  count(*) > 0 AND bool_and(
    x.flag IS NULL
    AND x.linear_feature_id = dv.linear_feature_id
    AND abs(x.downstream_route_measure - dv.downstream_route_measure) < 0.001
    AND dv.position_parent_subid IS NOT NULL
    AND dv.position_parent_subid IS DISTINCT FROM x.fwa_parent_subid
    AND x.fwa_parent_subid = (
      WITH RECURSIVE up AS (
        SELECT o.dowsubid AS subid, 1 AS n FROM fwapg.pcic_outlets o WHERE o.subid = x.subid
        UNION ALL
        SELECT o.dowsubid, up.n + 1 FROM up INNER JOIN fwapg.pcic_outlets o ON o.subid = up.subid
        WHERE NOT EXISTS (SELECT 1 FROM fwapg.pcic_fwa_crosswalk a WHERE a.subid = up.subid AND a.flag IS NULL)
      )
      SELECT up.subid FROM up ORDER BY up.n DESC LIMIT 1
    )
  ) AS result
FROM fwapg.pcic_diversions dv
INNER JOIN fwapg.pcic_fwa_crosswalk x ON x.subid = dv.subid;

-- the Nechako Reservoir (NewGraphEnvironment/fwapg#24): PCIC's tree sends it out
-- through the Skins Lake spillway (outlet 1007550 to 1008709, then the Cheslatta),
-- the FWA through Kenney Dam. Before the diversion was listed, 483 of the 487
-- outlets in LEUT, UEUT, UNRS and LNRS were unplaced and the reservoir's segments
-- carried about 0 m3/s. Measured after: see the README's caveats
WITH outlets AS (
  SELECT x.flag
  FROM fwapg.pcic_fwa_crosswalk x
  INNER JOIN fwapg.pcic_outlets o ON o.subid = x.subid
  INNER JOIN whse_basemapping.fwa_watershed_groups_poly g ON ST_Intersects(g.geom, o.geom)
  WHERE g.watershed_group_code IN ('LEUT', 'UEUT', 'UNRS', 'LNRS')
)
SELECT 'placed >= 90% of the Nechako Reservoir groups'' outlets with a candidate' AS test,
  count(*) FILTER (WHERE flag IS NULL)::numeric / nullif(count(*) FILTER (WHERE flag IS DISTINCT FROM 'no_candidate'), 0) >= 0.9 AS result
FROM outlets;

-- the reservoir's water leaves on PCIC's route: Knewstubb Lake's exit segment
-- carries outlet 1007550's PCIC outflow, the spillway outlet 1008709 its own
-- (gauge 08JA013), and the Nechako canyon just below Kenney Dam only local runoff
-- (0.13 m3/s before the diversion was listed)
WITH pcic AS (
  SELECT q.subid, avg(q.q_m3s) AS q FROM fwapg.pcic_outlet_monthly q
  WHERE q.subid IN (1007550, 1008709) GROUP BY q.subid
),
seg AS (
  SELECT l.label, avg(d.q_m3s) AS q
  FROM (VALUES ('exit', 288852.5::float8), ('canyon', 288500)) AS l(label, measure)
  CROSS JOIN LATERAL (
    SELECT s.linear_feature_id FROM whse_basemapping.fwa_stream_networks_sp s
    WHERE s.blue_line_key = 356362759 AND s.downstream_route_measure <= l.measure
    ORDER BY s.downstream_route_measure DESC LIMIT 1
  ) s
  INNER JOIN fwapg.pcic_discharge_monthly d ON d.linear_feature_id = s.linear_feature_id
  GROUP BY l.label
),
acc AS (
  SELECT m.subid, avg(m.q_acc) AS q FROM fwapg.pcic_subbasins_monthly m
  WHERE m.subid = 1008709 GROUP BY m.subid
)
SELECT 'Nechako Reservoir: exit carries 1007550''s PCIC flow, spillway 1008709 within 5%, canyon under 1 m3/s' AS test,
  coalesce(
    (SELECT abs(seg.q - pcic.q) <= 0.05 * pcic.q FROM seg, pcic WHERE seg.label = 'exit' AND pcic.subid = 1007550)
    AND (SELECT abs(acc.q - pcic.q) <= 0.05 * pcic.q FROM acc, pcic WHERE pcic.subid = 1008709)
    AND (SELECT seg.q < 1 FROM seg WHERE seg.label = 'canyon'),
    false) AS result;

-- a diversion's area is taken off the sub-basin its exit drains to on the FWA (its
-- position parent) and not off the one its flow goes to (pcic_crosswalk06_subbasins.sql):
-- the flow parent's local area is its upstream area less that of the outlets whose
-- position drains to it, and the position parent's has the diversion's taken off
WITH kids AS (
  SELECT coalesce(dv.position_parent_subid, x.fwa_parent_subid) AS parent, sum(sb.upstream_area_ha) AS area
  FROM fwapg.pcic_fwa_crosswalk x
  INNER JOIN fwapg.pcic_subbasins sb ON sb.subid = x.subid
  LEFT JOIN fwapg.pcic_diversions dv ON dv.subid = x.subid
  GROUP BY 1
)
SELECT 'a diversion''s area comes off its position parent''s sub-basin, not its flow parent''s' AS test,
  count(*) > 0 AND bool_and(
    abs(r.local_area_ha - (r.upstream_area_ha - coalesce(k.area, 0))) <= 0.01
    AND p.local_area_ha <= p.upstream_area_ha - t.upstream_area_ha + 0.01
  ) AS result
FROM fwapg.pcic_diversions dv
INNER JOIN fwapg.pcic_fwa_crosswalk x ON x.subid = dv.subid
INNER JOIN fwapg.pcic_subbasins t ON t.subid = dv.subid
INNER JOIN fwapg.pcic_subbasins r ON r.subid = x.fwa_parent_subid
INNER JOIN fwapg.pcic_subbasins p ON p.subid = dv.position_parent_subid
LEFT JOIN kids k ON k.parent = r.subid;

-- and in the weights (pcic_crosswalk07_segments.sql): the Nechako canyon just below
-- Kenney Dam takes the reservoir's area off its share and not its flow, and the
-- spillway outlet's own segment takes the reservoir's flow
SELECT 'Nechako Reservoir weights: canyon share under 0.1 without 1007550, spillway segment with it' AS test,
  coalesce(
    (SELECT w.share < 0.1 AND NOT 1007550 = ANY(w.upstream_subids)
     FROM fwapg.pcic_segment_weights w
     WHERE w.linear_feature_id = (
       SELECT s.linear_feature_id FROM whse_basemapping.fwa_stream_networks_sp s
       WHERE s.blue_line_key = 356362759 AND s.downstream_route_measure <= 288500
       ORDER BY s.downstream_route_measure DESC LIMIT 1))
    AND (SELECT 1007550 = ANY(w.upstream_subids)
     FROM fwapg.pcic_segment_weights w
     INNER JOIN fwapg.pcic_fwa_crosswalk x ON x.linear_feature_id = w.linear_feature_id
     WHERE x.subid = 1008709),
    false) AS result;

-- a diversion's flow enters the network once: at its PCIC ancestor's own segment
SELECT 'each diversion is in exactly one segment''s upstream_subids, its PCIC ancestor''s' AS test,
  count(*) > 0 AND bool_and(n = 1 AND on_receiving) AS result
FROM (
  SELECT dv.subid, count(w.linear_feature_id) AS n,
    coalesce(bool_and(w.linear_feature_id = r.linear_feature_id), false) AS on_receiving
  FROM fwapg.pcic_diversions dv
  INNER JOIN fwapg.pcic_fwa_crosswalk x ON x.subid = dv.subid
  INNER JOIN fwapg.pcic_fwa_crosswalk r ON r.subid = x.fwa_parent_subid
  LEFT JOIN fwapg.pcic_segment_weights w ON dv.subid = ANY(w.upstream_subids)
  GROUP BY dv.subid
) d;

-- inside the reservoir: the Eutsuk River at the outlet of Eutsuk Lake (gauge
-- 08JA028, PCIC outlet 1001917, 45 m3/s) was broken_chain and carried 0.024 m3/s
WITH annual AS (
  SELECT m.subid, avg(m.q_acc) AS q_acc, avg(q.q_m3s) AS q_pcic
  FROM fwapg.pcic_subbasins_monthly m
  INNER JOIN fwapg.pcic_outlet_monthly q ON q.subid = m.subid AND q.month = m.month
  WHERE m.subid = 1001917
  GROUP BY m.subid
)
SELECT 'Eutsuk outlet 1001917 is placed and within 5% of PCIC' AS test,
  coalesce(bool_and(abs(q_acc - q_pcic) <= 0.05 * q_pcic), false) AS result
FROM annual;
