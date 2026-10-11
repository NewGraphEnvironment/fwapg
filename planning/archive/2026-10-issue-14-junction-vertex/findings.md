# Findings — PCIC crosswalk: flow and placement at a tributary junction's vertex (#14)

## Issue context

**If we fix it:** flow per segment steps up at the junction itself, and the PCIC outlets that sit on a junction vertex land on the side of it their PCIC series describes. **If we don't:** at about a quarter of tributary junctions the main-stem segment just *above* the confluence carries the tributary's flow, and 6 outlets are placed above a confluence whose flow they include.

Both come from the same convention: FWA measures run `[downstream_route_measure, upstream_route_measure)`, and a code junction's measure equals the `downstream_route_measure` of the main-stem segment that starts there.

## 1. Segment flow (`extras/pcic_crosswalk/sql/pcic_crosswalk07_segments.sql`, about lines 94-96)

An outlet above the sub-basin counts as passing a segment when `fwapg.blk_on_or_upstream(s.blue_line_key, s.downstream_route_measure, ...)`, whose test is `>=`. So a tributary joining at the segment's own `downstream_route_measure` counts as passing the segment above the confluence.

Example, from the build on branch `13-run-blue-line-paths-pcic-crosswalk-and-m`: blue line 356362488, June:

| segment | drm | local code | q (m3/s) |
|---|---|---|---|
| 701317270 | 82790.50 | `100.077501.955583.005332` | 695.19 |
| 701317184 | 83036.96 | `100.077501.955583` | **684.85** |
| 701317113 | 83266.92 | `100.077501.955583` | 13.97 |

A code-check reviewer counted 1,464 of 5,892 single-step tributaries with June flow over 1 m3/s where the jump lands on the segment above the junction. That count has not been re-derived; the example above has. It is one short segment per junction, and the monthly totals are unaffected.

## 2. Ties in placement (`extras/pcic_crosswalk/sql/pcic_crosswalk02_candidates.sql`)

#13 made the nearest-segment choice deterministic: on a tie (a probe on the vertex two segments of one blue line share, about 1% of outlets) the outlet takes the segment starting there, the upper one. That is right when the tributary entering at that vertex is the outlet's PCIC sibling. At **6 outlets** (12007835, 2007294, 4000204, 4000212, 5014089, 9001132) the tributary is the outlet's own PCIC child, so the outlet should be below the confluence. Accumulated flow is still right (the FWA-parent rule in 06 is `<=`), but the sub-basin's local area is short by the tributary's, and the published row puts the outlet above the confluence. Documented as a caveat in the PCIC README.

## Possible fix

Make the passing test strict for segments (or compare by segment rather than by measure), and at a tie in 02, take the lower segment when a PCIC child's blue line joins at that vertex. Both change stored outputs, so they want a rerun and a comparison against the current build.

## Plan-mode measurements (2026-10-11, local fresh-db, build from #13)

Measured on the current build (local fresh-db, 2026-10-11):
- 37,667 outlets are placed, and 174 of them sit on a vertex (excluding line mouths).
- Exactly **6** of those have a placed PCIC child joining at that measure (7 children), which matches the issue.
- **No** PCIC sibling joins at a vertex outlet.
- Of the first-step junctions in `fwapg.blk_paths`, 1,568,353 fall within 1 µm of a segment start. (Corrected by the plan review, which counted against 1,570,499 junctions: 1,529,850 exactly on a start and 1,569,124 within 1 mm. Code junctions are always exact; touch junctions are exact at only 41,098 of 71,331, because interpolation along a segment adds float noise.) Part 1's boundary therefore applies at essentially every junction.

## Approach

- **Part 1:** make the passing test in 07 strict: the outlet must join `s`'s line *above* `s`'s start. `fwapg.blk_on_or_upstream` stays as it is. Its other callers (04 select, 05 demote) compare **points**, where `>=` is right, and it belongs to the `blue_line_paths` extra.
- **Part 2:** move the outlet after placement, not during it. Placement (04 and 05) runs from the root upward, so a parent's tie in 02 would be decided before its children are placed. Instead, at the top of 06 and before `fwa_parent_subid` is computed: an outlet on a vertex whose placed PCIC child joins its line at that measure is moved to the segment **ending** there on the same blue line. Its measure does not change, so placement validity and the vote are unaffected.
  - After the move, 06's parent rule (`o.drm <= M`) and 07's segment ownership (`seg_measure <= s.drm`) give the right answer with no other change.
  - The child joins above the outlet's new segment start, so the outlet's segment carries its accumulated flow: the existing QA test "outlet segments carry accumulated flow" still holds.

## Phase 1: the new QA tests on the current build (2026-10-11)

Both return `f` on the #13 build, before any fix:
- `no placed outlet sits above a confluence its PCIC child joins at`: f (the 6 outlets).
- `tributary 356359224 steps up flow below its junction, not above it`: f. June on blue line 356362488 is 13.97 (701317113) -> 684.85 (701317184) -> 695.19 (701317270) m3/s. 76 placed outlets on 356359224 have a path joining 356362488 at 83036.9599489122, which is exactly 701317184's `downstream_route_measure`.

Adjacent FWA segments' measures are not bit-equal: 701317270's `upstream_route_measure` is 83036.95988380806 against 701317184's `downstream_route_measure` of 83036.9599489122 (6.5e-5 apart). So the tests compare within 1 mm, and the Phase 3 move picks "the segment below" by order on the blue line, not by `upstream_route_measure = measure`.

## Phase 2-3 design measurements (2026-10-11)

- Vertex outlets (measure = segment start, > 0) with any blue line's path joining at their measure: **94 outlets, 95 lines**. Only 6 of those lines carry a placed PCIC child. So the `<=` in the step>0 rules (06 `fwa_parent_subid`, 07 `nearest`) mattered beyond the 6: the tributary's segments went to an outlet on the upper segment, whose upstream area excludes the tributary. Both rules now require the outlet's segment to start below the junction.
- The segment below each of the 6 outlets: 5 are usable, at gaps of -0.0007 to +0.0004 m from the vertex. 5014089's (707098172, 43.8 m, edge 1250, Midge Creek, KOTL) is not in `fwa_streams_watersheds_lut`. Its next usable segment below is 707098394, at about 44 m. Its PCIC children are 5014087 (same blue line, above) and 5014088 (blue line 356563710, which joins at the vertex).

## Intermediate run (`data/run14.log`, 88a60d0, 2026-10-11 16:14-16:43 UTC)

All QA passed, including both Phase 1 tests (`f` -> `t`). The move updated 6 outlets. Against the #13 snapshot:
- Crosswalk: 6 rows changed (`linear_feature_id`; measure > 1 mm only for 5014089, 15351.363 -> 15307.561). `fwa_parent_subid`, flag and anchor are identical everywhere.
- Output segments: 3,377,050 -> 3,377,037. The 13 dropped are on five secondary-flow lines (edge 1100/1150/1350/1450) that join two coastal rivers at measure 0 (KITL 360871314 and GRAI 360873432; neither river has a path, so they drain to the sea). Under the strict rule they are below the rivers' lowest outlets, the same as the Toba caveat. Review G3.
- 4,601 segments changed flow by more than 0.001 m3/s in some month, 3,843 of them junction-start segments. 2,309 changed by more than 1 m3/s; 2,001 fell by more than 1 in June and 51 rose.
- Flow summed over river mouths (lines with no path, lowest segment, annual mean): 21,366.4 before and after. Root outlets' segments: 21,435.97 before and after.
- Review metric (junctions within 1 mm of a segment start, joining line > 1 m3/s in June, step on the upper segment): **2,373 of 18,942 before, 678 after** (the review counted 2,720 of 20,745 on the #13 build with its own query). Of the 678, all are exact junctions. 345 have a placed outlet higher on the upper segment whose PCIC flow includes the tributary (an unplaced PCIC child anchored to it: the review's scope note). The rest are area shares: 133 where the upper segment and the tributary's mouth share a fundamental watershed polygon, the others where the lookup gives the upper segment the tributary's area.
- S1, junction-start segments whose June flow exceeds the segment below's by more than 1 m3/s: 776 before, 668 after.
- `anchor_subid` for a placed outlet is its nearest placed ancestor (36,896 = `dowsubid`; none = own `subid`), and matching by it gives the same 7 children at the same 6 outlets on #13 (review G1).

## Phase 3b QA tests fire (16:50 UTC)

Against the #13 snapshot, the vertex test, the FWA-child invariant and the population ceiling (<= 1,000) all return `f`. On the intermediate build all three return `t`. They take about 9 s together.

## Code-check round 1 (planning/active/review-round1.md)

The reviewer found no defect in the current build and two guard blind spots with no instance today, both of which would publish short flow silently:
- An outlet at its line's mouth whose PCIC descendant joins there. The strict step>0 rule parents the descendant below it, and the move cannot help (no segment below). Fix: QA test 1 no longer exempts measure 0, so such a case stops the job. Measured: 7000406 (GRAI) and 8002298 (KITL) sit at mouths where lines join, and no placed outlet is on those lines.
- A stacked pair (two placed outlets within 1 mm on one line). Moving one below the other would reverse them on the FWA. Fix: the move skips such an outlet, which stays on its vertex, so QA test 1 stops the job. Mutation test: planting a duplicate of 4000204 on temp tables made the move select 5 outlets instead of 6 (4000204 skipped).

## Code-check round 2 (planning/active/review-round2.md)

- **Bug, in the pre-branch build too:** the step>0 test `o.downstream_route_measure <= st.measure` had no tolerance. Outlets 5012573, 5017485 and 206006820 sit on the segment below a junction but 1e-14 to 1e-10 m above its measure, so their tributaries skipped them. Reproduced: blue line 356567538 (2,130 ha, joining 356369704 at 73.6866952293771, outlet 5012573 at 73.68669522937711) has 0 m3/s in all 12 months on all 360 segments, in both builds. Its segments went to 5012569, whose local area is -28,693 ha (share 0). Fix: `<= st.measure + 0.001` in 06 and 07, plus a QA regression test ("tributary 356567538 carries flow", `f` on the pre-branch build).
- **Inside a fix (the 1 mm landing):** `least(x.drm, b.urm - 0.001)` returns the junction measure itself wherever the segment below overlaps the vertex by more than 1 mm (2.2% of FWA boundaries). Fix: `least(x.drm, b.urm) - 0.001`.
- **Inside a fix (round 1's stacked check):** it looked only within 1 mm of the old position, but a move can go up to 100 m. Fix: the check covers the band the move crosses, from the landing (less 1 mm) to the old position.

Enumeration that ends the class (comparisons of measures with no tolerance, across sources): every comparison of measures in 06, 07 and `qa.sql` was listed by grep. Those across sources (a path's junction measure against a segment start or an outlet's interpolated measure; an outlet's measure against a vertex) all carry 1 mm: 06:69, 82, 84, 90-91, 143; 07:79, 112; qa 120, 122, 151, 189, 194. Those left exact compare two FWA segment starts on the same line from the same table (07:78, 105; 06's step-0 tuple; `s.drm > 0` at 06:81), which are equal by construction where they should be.

## Code-check round 3 (planning/active/review-round3.md)

- **The mechanism** behind rounds 1-3: deciding which side of a junction something is on by comparing two measures that should name the same point but are built from different FWA fields. On the FWA, `upstream_route_measure` misses the next segment's `downstream_route_measure` by 1 mm to 1 cm at about 137k boundaries (by up to 9.3 mm), while `downstream_route_measure + length_metre` agrees with it (over 1 mm at only 52, at most 3 mm). Outlet measures (02) and touch-junction measures (`blue_line_paths.sql`) are `drm + ST_LineLocatePoint * length`, so they agree with segment starts. The comments saying adjacent measures "differ in the last digits" were false for `urm` (corrected).
- **Inside a fix (the landing, again):** after a skip, the move landed 1 mm below `b.upstream_route_measure`, not below the start of the segment directly above b, where lines join. 5014089 landed 0.16 mm below the junction of side channel 356367323 (3.3 m3/s in June), one step from the round-2 zero-flow class. Fix: `least(x.drm, b.urm, top_measure) - 0.001`, where `top_measure` is the start of the segment directly above b; the stacked band uses the same expression. Checked: all 6 landings now sit at least 1.000 mm below the junction at b's top (they were 0.16 to 1.7 mm).
- **Enumeration that ends the loop:** every place a position is derived from `upstream_route_measure`. 06:53 (landing) and 06:90 (band) are fixed. 06:70 is the 100 m reach window, which millimetres cannot move. 07:52 carries the column into `pcic_segments` and never compares it. 00-05, `qa*.sql` and `blue_line_paths.sql` do not read it. Together with round 2's list (every comparison across sources has 1 mm), nothing positions an outlet or junction from the field that disagrees.
- **Out of scope, no instance:** the round-2 class also reaches placement in 04/05 (`blk_on_or_upstream`, `>=` with no tolerance). An outlet 1e-14 m above a junction blocks a child on that tributary from validating against it. The build has 4 such outlets, and none has a PCIC child on the joining tributary. Placement is not changed by #14; noted for the review in #8.

## Final run (`data/run14b.log`, eae70af, 2026-10-11 17:23-17:51 UTC)

All 15 QA tests passed: 10 existing and 5 new (vertex outlets, tributary 356567538, FWA-child invariant, tributary 356359224, junction ceiling). The move updated 6 outlets.

**Fingerprint** (for wet#58 and fwapg#9): `fwa_stream_networks_discharge_monthly` 40,524,444 rows, 3,377,037 segments, `sum(round(q_m3s::numeric, 6))` = 178035348.248310. `pcic_fwa_crosswalk` 48,716 rows. (#13: 40,524,600 rows, 3,377,050 segments, sum 178168114.938520.)

Against the #13 build:
- Crosswalk: 6 rows changed (segment, local code, measure; 5014089 also distance and a NULL `candidate_rank`). `fwa_parent_subid`, flag and anchor are identical everywhere. Landings: 2007294 899883.296 -> .294, 4000204 90814.780 -> .778, 4000212 2098.048 -> .047, 5014089 15351.363 -> 15307.559, 9001132 3084.100 -> .099, 12007835 943.358 -> .357.
- Segments: 4,695 changed by more than 0.001 m3/s in some month, 3,892 of them junction-start segments. 2,300 changed by more than 1 m3/s (2,005 fell in June, 38 rose).
  - 1,052 segments that had no flow in any month now carry some: the tributaries an outlet skipped by float noise (round 2), 356567538 among them.
  - 135 segments now carry none, against some before. On every one, nothing above it on its line carries flow, so its only flow was a tributary's step landing one segment too high. Edge types: 1000 (65, mostly small STHM streams), 1410 connectors (20), 1100 secondary flow (12), 1200 (9), 1475 lake arms (8), and others. The largest was 703314562 (THOM, a 144 m, 1 ha construction line) at 734 m3/s.
  - 13 segments left the output (five secondary-flow lines at the KITL and GRAI mouths, as in the intermediate run).
- Junctions where the step lands on the segment above (review metric): 2,373 of 18,942 before and 678 of 18,941 after; under the QA ceiling of 1,000.
- Junction-start segments above the segment below's flow by more than 1 m3/s (S1): 776 before, 668 after.
- Flow summed at river mouths: 21,366.4 m3/s before and after. Root outlets' segments: 21,435.97 before and after.
- Gauges (`qa_gauges.sh`, `data/qa_gauges_run14b.log`): unchanged at 538 compared, 494 within 10% (114, 207, 134 and 39 by size class), 11 where another PCIC branch matches, 33 disagree. FWA flow changed at 2 of 604 gauges: 08ND007 Columbia above Nagle Creek 551.133 -> 544.148 m3/s (PCIC 7.19; one of the known Columbia side-channel cases) and 08NG042 Kootenay at Newgate 288.002 -> 288.186.
- Snapshot tables dropped after the comparison; wet#58 confirmed it does not need them.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| A mutation probe built by extracting the move's SELECT from 06 with an `awk` range ran past it: `sed -n '/A/,/B/p'` on a file where A recurs extracted the rest of 06, and psql executed it. The crosswalk references had been redirected to a temp table, but the `fwapg.pcic_subbasins*` statements ran for real and created a stray `fwapg.pcic_subbasins`. | Checked `pg_stat_user_tables`: the crosswalk's update count (36,998) and last analyze (16:35) are the job's, and the monthly table and snapshots are untouched. Dropped the stray table. Redid the probe with the SELECT written out by hand over temp tables only. Never pipe extracted job SQL into psql. |
