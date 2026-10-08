# Review round 5: junction fix in sql/pcic_crosswalk01_paths.sql

Scope: only the junction derivation (rules 1-3), the walk, the cycle check, and the two new QA
tests in sql/qa.sql. All measurements are read-only SELECTs on the local fwapg DB after the full
rebuild: 1,482,199 code + 71,331 touch parent rows, 35,987 placed outlets.

## Enumeration (each case: right / wrong, measured)

1. **Acyclicity under rules 1 and 2: right, proven.**
   - Take potential = 2*nlevel(wscode) + (1 if side channel). It strictly decreases along every
     parent edge:
     - code edge: main(n) to main(n-1);
     - touch from a main: to a strictly-ancestor code, at most 2(n-1)+1 < 2n;
     - touch from a side channel: to a strictly-ancestor code (< 2n+1), or to its own
       watershed_key at the same code (2n < 2n+1).
   - The proof needs a line's segment wscode to equal its blks wscode, and each watershed_key line
     to be a main. Measured on non-6010, non-999 segments:
     - 0 lines have more than one wscode or watershed_key;
     - 0 of 74,430 side channels have a watershed_key line that is itself a side channel; 0 have a
       missing key line;
     - 3 side channels have a key line whose wscode differs and is not an ancestor. Those 3 can
       only attach strictly lower, so they are safe.
   - The DO block can never fire. It is harmless.
2. **Mains with no expected main (26,097 + 7 top-level): right. These are unchanged from before.**
   - 25.9k are 9xx coastal codes, whose parent is the coastline.
   - The rest are 200/800 codes whose parent river is outside BC.
3. **Mains with an expected parent but no code junction and no touch (596): mostly right.**
   - By watershed group they are transboundary: SIML (Similkameen) 35, SMOK 46, KUSR 46, TATR 34,
     KOTL (Moyie/Yahk) 15, ELKR (Kishinena/Sage) 9, LPCE (Pouce Coupe) 23, LARL (Upper Priest) 18,
     and so on.
   - Placed outlets on them are PCIC roots: 0 of the 677 roots has a placed PCIC ancestor. This is
     consistent with water leaving BC.
   - 151 have a lower-code line within 500 m of the mouth. All but 2 carry 0 placed outlets: Draney
     Creek (OWIK, 2 placed) and Wilms Creek (INKR, 1). Not flagged.
4. **Side channels that lost their path (17,200): wrong. This is a regression introduced by the
   fix. See finding 1.**
   - 14,950 of them have a mouth that touches a sibling side channel of the same main (a braid
     rejoining through another braid). Rule 2 forbids that edge.
   - None touches its watershed_key within 1 m. Distance from mouth to main:
     - 1-10 m: 74
     - 10-100 m: 3,975
     - 100-500 m: 9,661
     - 500 m-1 km: 2,462
     - 1-5 km: 1,004
     - more than 5 km: 24
   - 46,439 lines (these 17,200 plus 29,239 tributaries whose path ends on one of them) cover
     132,380 segments and 41,925 km. Only 23 of those segments have a discharge row.
   - 352 broken_chain outlets have a rank-1 candidate whose path ends on a pathless side channel.
     Each has a PCIC anchor in BC, and q_mean reaches 129.5 m3/s.
   - Worst case: the Kitsumkalum River (360883243, KLUM, about 130 m3/s). Its mouth touches Skeena
     braid 360222215, and that braid touches braid 360222216 but not the Skeena main. The result is
     0 placed outlets on the Kitsumkalum, 105 broken outlets, and 0 of 11,586 segments under
     400.195432 with discharge.
   - Also lost: Exchamsiks (63 m3/s), Exstew (41), Kasiks (33), Cayoosh Creek and the Seton
     tributaries (49 outlets), Shames, Hope Slough and others.
   - Flow is still conserved at the anchors (runoff is lumped there), so PCIC-agreement stats do
     not show the loss. The output does: segments with no discharge at all, and the drop in placed
     outlets from 36,380 to 35,987.
   - Losing these paths is right only for distributaries that reach the sea or leave BC, such as
     the roughly 1k top-level Fraser/Skeena delta side channels. It is wrong for the braids.
5. **Code junctions whose mouth meets a side channel of the parent: wrong in some cases. Rule 1 is
   unchanged, but this is the same site.**
   - Of the 8,895 code junctions more than 100 m from the mouth, 8,570 have a mouth that touches a
     side channel of the expected parent. For 7,212 of those, the side channel joins the parent
     main directly. For 942, the side channel's own junction is more than 100 m from the code
     junction, and in every case it is downstream of it.
   - 205 placed outlets on the parent sit between the two junctions. 23 of them (11%, against 1.1%
     overall) carry more than 5% too much flow, and none carries too little. The tributary is
     added above an outlet that its water reaches only below.
   - Example: Birkenhead River (356360441). Its code junction is at 87,236 on the Lillooet. Its
     mouth is on side channel 355993478, which joins the Lillooet at 85,225. Outlet 4008011 at
     86,597 gets 191.55 m3/s from FWA against 173.14 from PCIC.
   - Of the 412 junctions more than 1 km away, 9 carry placed outlets:
     - July Creek (KETL, 2,187 m): right. It is a 6010 connector, and the Kettle re-enters BC.
     - Malde Creek: right. The projection equals the junction.
     - Bowes, Salmon, Meadow, Humphrys, Feak, Craig: right, by PCIC agreement. The outlets between
       the junctions match PCIC exactly.
     - Birkenhead: wrong, as above.
6. **Mouth definition: right.**
   - There are no multipart segments (0 rows with ST_NumGeometries > 1), so ST_GeometryN(geom, 1)
     is the whole segment.
   - 35 lines have a lowest segment that is 6010 (a connector that leaves and re-enters BC). All
     35 are mains.
     - 29 get code junctions, so the mouth affects only junction_gap_m. Two of them carry placed
       outlets, both Kettle tributaries (356564858 with 20, July Creek 380887745 with 4); both are
       correct because the Kettle re-enters BC.
     - The other 6 have no parent and 0 placed outlets.
7. **The two new QA tests.**
   - Test "junctions not from codes are within 1 m" cannot fail. by_touch filters
     `ST_DWithin(s.geom, e.mouth, 1)` and stores `ST_Distance(t.geom, e.mouth)` for the same row.
     The only methods are 'code' and 'touch'.
   - Test "the Okanagan has no path" can fail. Re-introducing an unbounded projection would
     reattach 356570548 (Okanagan, 300.432687). It also passes vacuously when pcic_blk_paths is
     empty. Other tests would catch an empty table.
   - Neither test detects case 4: a BC line losing its path.

## Findings

- **[severity: bug]** extras/pcic_crosswalk/sql/pcic_crosswalk01_paths.sql:112-113 — Rule 2 lets a
  side channel attach only to its own watershed_key or to a strictly lower code. A braid that
  rejoins its main through another braid therefore gets no path.
  - Scale: 17,200 side channels, with 14,950 touching a sibling side channel. With the tributaries
    behind them, that is 46,439 lines and 132,380 segments (41,925 km), and only 23 segments have
    discharge.
  - Damage: 352 PCIC outlets are pushed to broken_chain, including the whole Kitsumkalum River
    (about 130 m3/s, 0 of 11,586 basin segments with discharge), Exchamsiks, Exstew, Kasiks and
    Cayoosh.
  - The header calls rule-3 lines "lines whose water leaves BC ... and a few orphans". That is not
    what is happening.
  - Acyclic fix: attach in rounds. A side channel whose mouth touches a sibling side channel that
    already has a parent from an earlier round takes that sibling as its parent. Repeat until no
    rows are added. Each round attaches only to lines attached earlier, so no cycle is possible. A
    distance-bounded projection onto watershed_key is an alternative.
  - Add a QA test that fails on this, for example: "Kitsumkalum 360883243 has a path", or "no
    side channel lacks a path when its watershed_key has one".
- **[severity: bug]** extras/pcic_crosswalk/sql/pcic_crosswalk01_paths.sql:74-92 — Rule 1 runs
  before rule 2 even when the mouth touches a side channel of the expected parent.
  - The code junction (the main-stem segment whose localcode is the tributary's code) is then
    upstream of where the side channel, and so the tributary's water, actually rejoins the main.
  - 942 junctions sit more than 100 m upstream of the touched side channel's own junction.
  - 205 placed parent outlets fall between the two, and 23 of them carry more than 5% too much
    flow against PCIC. Example: Birkenhead into the Lillooet, outlet 4008011, 191.55 against
    173.14 m3/s.
  - Fix: when the mouth touches a side channel of the expected parent and that side channel has a
    parent, use the touch (via the side channel) instead of the code junction. This becomes safe
    once finding 1 gives braids paths.
- **[severity: fragile]** extras/pcic_crosswalk/sql/qa.sql:75-79 — The test "junctions not from
  codes are within 1 m of the mouth" is tautological. by_touch already filters on
  `ST_DWithin(..., 1)` and stores the same distance, so the test cannot fail. It does not guard the
  Okanagan defect class: that guard is the next test, which checks a single line. It also does not
  guard the braid regression above.
