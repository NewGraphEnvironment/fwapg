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

## Errors Encountered

| Error | Resolution |
|-------|------------|
