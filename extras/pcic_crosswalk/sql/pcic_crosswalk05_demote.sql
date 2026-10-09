-- Find placed outlets that are more likely misplaced than the outlet that broke
-- against them, and add them to fwapg.pcic_demoted for the next placement round.
-- Prints the number of outlets demoted this round.
--
-- Outlet s breaks against its parent a (s has no candidate on or upstream of
-- a). Either s or a is wrong. Blame a when s has a candidate on or upstream of a's
-- own anchor (so s fits the chain once a is skipped) and s carries at least half
-- of a's PCIC network.

INSERT INTO fwapg.pcic_demoted (subid, round)
SELECT DISTINCT a.subid, :round
FROM whse_basemapping.pcic_fwa_crosswalk s
INNER JOIN whse_basemapping.pcic_fwa_crosswalk a ON a.subid = s.dowsubid
INNER JOIN fwapg.pcic_outlets os ON os.subid = s.subid
INNER JOIN fwapg.pcic_outlets oa ON oa.subid = a.subid
LEFT JOIN whse_basemapping.pcic_fwa_crosswalk g ON g.subid = a.anchor_subid
WHERE s.flag = 'broken_chain'
AND s.anchor_subid = a.subid
AND os.subtree_size * 2 >= oa.subtree_size
AND EXISTS (
  SELECT 1
  FROM fwapg.pcic_candidates y
  WHERE y.subid = s.subid
  AND (
    g.subid IS NULL
    OR fwapg.blk_on_or_upstream(g.blue_line_key, g.downstream_route_measure, y.blue_line_key, y.downstream_route_measure)
  )
)
ON CONFLICT DO NOTHING;

SELECT count(*) FROM fwapg.pcic_demoted WHERE round = :round;
