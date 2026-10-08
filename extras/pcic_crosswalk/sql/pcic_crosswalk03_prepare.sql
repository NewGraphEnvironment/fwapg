-- Setup for placing outlets (pcic_crosswalk04_select.sql, pcic_crosswalk05_demote.sql):
-- the size of each outlet's PCIC subtree, and an empty list of demoted outlets.
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

-- outlets found to be misplaced by pcic_crosswalk05_demote.sql; refilled each run
DROP TABLE IF EXISTS fwapg.pcic_demoted;
CREATE TABLE fwapg.pcic_demoted (subid integer PRIMARY KEY, round integer);
