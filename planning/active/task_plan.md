# Task: PCIC crosswalk: flow and placement at a tributary junction's vertex (#14)

**If we fix it:** flow per segment steps up at the junction itself, and the PCIC outlets that sit on a junction vertex land on the side of it their PCIC series describes. **If we don't:** at about a quarter of tributary junctions the main-stem segment just *above* the confluence carries the tributary's flow, and 6 outlets are placed above a confluence whose flow they include.

Branch `14-pcic-crosswalk-flow-and-placement-at-a` off `newgraph`; PR `--base newgraph`.

## Phase 1: QA tests that fail on the current build
- [x] `sql/qa.sql`: "no placed outlet sits above a confluence its PCIC child joins at". The test looks for placed outlets on a vertex (measure = segment start, > 0) where a placed child (`dowsubid = subid`, on another blue line) has a path joining the outlet's line at that measure, and expects 0. It uses only the crosswalk, `fwapg.blk_paths` and the FWA streams.
- [x] `sql/qa.sql`: a named regression in the style of the Kitsumkalum test. On blue line 356362488 in June, segment 701317184 (starting at the junction) carries less than half of 701317270 (below it).
- [x] Run both against the current build. Both should return `f`. Record the values in `findings.md`.

## Phase 2: Segment flow steps up at the junction (part 1)
- [x] `sql/pcic_crosswalk07_segments.sql`: replace the `blk_on_or_upstream` call for outlets on another blue line with a strict test: an `EXISTS` over `fwapg.blk_paths` where the outlet's path reaches `s.blue_line_key` at `measure > s.downstream_route_measure`. The comment states why the test is strict here and why the shared function is unchanged.
- [x] Update the header comment in 07 and README step 6 to match.
- [x] (Added in implementation.) The same strictness for which outlet a tributary's water reaches: on the lines of its path, the outlet's segment must start below the junction (`o.seg_measure < measure - 0.001`), in 07's `nearest` (segment ownership) and 06's `fwa_parent_subid` rule, which must agree. Measured: 94 vertex outlets have some blue line joining exactly at their measure (95 lines), of which only 6 are PCIC children. For the other 88, the `<=` rule handed the tributary's segments to an outlet on the upper segment, whose upstream area excludes the tributary.

## Phase 3: Outlets with a PCIC child at their vertex move below the confluence (part 2)
- [x] `sql/pcic_crosswalk06_subbasins.sql`, before `fwa_parent_subid`: an outlet on a vertex (measure = its segment's start, > 0) whose placed PCIC child joins its line at that measure moves to the nearest usable segment below on its blue line, within 100 m. Usable means in `fwa_streams_watersheds_lut`, edge type not 1425/6010, and with a local code. `linear_feature_id`, measure, `localcode_ltree`, `wscode_ltree`, `watershed_group_code` and `distance_to_stream` (from `fwapg.pcic_outlets.probe_geom`) are all updated. If nothing usable is in reach, the outlet stays and the Phase 1 test stops the job. 5014089 (Midge Creek, KOTL) needs the 100 m: the 43.8 m segment below it, 707098172, is not in `fwa_streams_watersheds_lut`, so it moves about 44 m down to 707098394.
- [x] Add a pointer from the tie-rule comment in 02 to the move in 06, and update README step 3 (the "at 6 outlets" passage) and the caveats.

## Phase 3b: Fold in the plan review (review-1.md), then a final rerun
- [ ] Match the child by `anchor_subid = x.subid` (a placed descendant through an unplaced child is in x's flow too) in the 06 move and QA test 1. It gives the same 7 children today; verify that.
- [ ] Land a moved outlet at `least(measure, upstream_route_measure - 0.001)`, at least 1 mm inside its segment, so which junction it sits below never rests on float noise. Set `candidate_rank` to NULL when the move goes more than 1 mm (the position is no longer a candidate), and say so in the README.
- [ ] QA: every placed outlet's FWA child on another blue line joins the parent's line at least 1 mm above the start of the parent's segment, mouths included. This guards the 06 and 07 step>0 rules against drifting apart.
- [ ] QA: a population ceiling on junctions where the step lands on the segment above, set from the intermediate run. The residual is not 0: touch junctions with no tributary outlet step by area share.

## Phase 4: Rerun and compare against the current build
- [ ] Snapshot the current outputs into scratch tables (`fwapg.pcic14_before_crosswalk`, `fwapg.pcic14_before_monthly`).
- [ ] Rerun `./pcic_crosswalk.sh` in the background: `data/run14.log` is the intermediate run on 88a60d0, `data/run14b.log` the final run after Phase 3b. Log to `data/run14*.log` (about 30 min; do not run the main-flow tree job at the same time). QA must pass, including both new tests.
- [ ] Compare against the snapshot:
  - the crosswalk should differ only at the 6 outlets (segment, measure, local code, distance), with `fwa_parent_subid` identical everywhere (assert it);
  - list the segments whose flow changed. Expect junction-start segments, the 6 outlets' sub-basins and their parents' (local areas change), the tributary lines that move to the sub-basin below, the lowest segments of lines joined at measure 0, and side_fallback junction segments;
  - count junction-start segments whose flow ends up above the segment below's (review S1);
  - derive the count of junctions where a tributary's step moved down, replacing the issue's unverified 1,464 of 5,892;
  - totals at root outlets' segments (`fwa_parent_subid IS NULL`) should be unchanged.
- [ ] `./qa_gauges.sh` against 494 of 538 within 10%, and update the README numbers that move.
- [ ] Drop the snapshot tables. Record the measurements in `findings.md`, with the log prefix `data/run14*` as evidence.

## Validation

- [ ] QA passes (`sql/qa.sql`, all `t`), and both new tests went `f` -> `t` across the fix
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
