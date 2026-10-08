-- Setup for placing outlets (pcic_crosswalk04_select.sql, pcic_crosswalk05_demote.sql):
-- the size of each outlet's PCIC subtree, the look-ahead voters, and an empty list
-- of demoted outlets.
-- The position test, fwapg.pcic_on_or_upstream, is in pcic_crosswalk01_paths.sql.

-- number of PCIC outlets at or above each outlet
ALTER TABLE fwapg.pcic_outlets DROP COLUMN IF EXISTS subtree_size;
ALTER TABLE fwapg.pcic_outlets ADD COLUMN subtree_size integer;
WITH RECURSIVE up AS (
  SELECT subid, subid AS member FROM fwapg.pcic_outlets
  UNION ALL
  SELECT up.subid, o.subid
  FROM up
  INNER JOIN fwapg.pcic_outlets o ON o.dowsubid = up.member
)
UPDATE fwapg.pcic_outlets o
SET subtree_size = s.n
FROM (SELECT subid, count(*) AS n FROM up GROUP BY subid) s
WHERE o.subid = s.subid;

-- the PCIC outlets up to three levels above each outlet, and which of their
-- candidates are "near" (within 25 m of their nearest): the voters for
-- pcic_crosswalk04_select.sql's look-ahead
DROP TABLE IF EXISTS fwapg.pcic_voters;
CREATE TABLE fwapg.pcic_voters AS
WITH RECURSIVE up AS (
  SELECT o.subid, c.subid AS voter, 1 AS level
  FROM fwapg.pcic_outlets o
  INNER JOIN fwapg.pcic_outlets c ON c.dowsubid = o.subid
  UNION ALL
  SELECT up.subid, c.subid, up.level + 1
  FROM up
  INNER JOIN fwapg.pcic_outlets c ON c.dowsubid = up.voter
  WHERE up.level < 3
)
SELECT up.subid, up.voter, y.blue_line_key, y.downstream_route_measure
FROM up
INNER JOIN fwapg.pcic_candidates y ON y.subid = up.voter
WHERE y.distance_to_stream <= (
  SELECT min(z.distance_to_stream) FROM fwapg.pcic_candidates z WHERE z.subid = up.voter
) + 25;
CREATE INDEX ON fwapg.pcic_voters (subid);
ANALYZE fwapg.pcic_voters;

-- outlets found to be misplaced by pcic_crosswalk05_demote.sql; refilled each run
DROP TABLE IF EXISTS fwapg.pcic_demoted;
CREATE TABLE fwapg.pcic_demoted (subid integer PRIMARY KEY, round integer);
