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

## Errors Encountered

| Error | Resolution |
|-------|------------|
