# Task: PCIC crosswalk: flow and placement at a tributary junction's vertex (#14)

**If we fix it:** flow per segment steps up at the junction itself, and the PCIC outlets that sit on a junction vertex land on the side of it their PCIC series describes. **If we don't:** at about a quarter of tributary junctions the main-stem segment just *above* the confluence carries the tributary's flow, and 6 outlets are placed above a confluence whose flow they include.

Branch `14-pcic-crosswalk-flow-and-placement-at-a` off `newgraph`; PR `--base newgraph`.

## Phase 1: QA tests that fail on the current build
- [x] `sql/qa.sql`: "no placed outlet sits above a confluence its PCIC child joins at". The test looks for placed outlets on a vertex (measure = segment start, > 0) where a placed child (`dowsubid = subid`, on another blue line) has a path joining the outlet's line at that measure, and expects 0. It uses only the crosswalk, `fwapg.blk_paths` and the FWA streams.
- [x] `sql/qa.sql`: a named regression in the style of the Kitsumkalum test. On blue line 356362488 in June, segment 701317184 (starting at the junction) carries less than half of 701317270 (below it).
- [x] Run both against the current build. Both should return `f`. Record the values in `findings.md`.

## Phase 2: Segment flow steps up at the junction (part 1)
- [ ] `sql/pcic_crosswalk07_segments.sql`: replace the `blk_on_or_upstream` call for outlets on another blue line with a strict test: an `EXISTS` over `fwapg.blk_paths` where the outlet's path reaches `s.blue_line_key` at `measure > s.downstream_route_measure`. The comment states why the test is strict here and why the shared function is unchanged.
- [ ] Update the header comment in 07 and README step 6 to match.

## Phase 3: Outlets with a PCIC child at their vertex move below the confluence (part 2)
- [ ] `sql/pcic_crosswalk06_subbasins.sql`, before `fwa_parent_subid`: `UPDATE` the crosswalk for vertex outlets with a placed PCIC child joining at their measure. Set `linear_feature_id`, `wscode_ltree` and `localcode_ltree` to the segment on the same blue line whose `upstream_route_measure` equals that measure, and keep the measure. Move only when that segment is usable (in `fwa_streams_watersheds_lut`, edge type not 1425/6010). The outlet stays put otherwise; that case is counted, and the Phase 1 test fails on it.
- [ ] Add a pointer from the tie-rule comment in 02 to the move in 06, and update README step 3 (the "at 6 outlets" passage) and the caveats.

## Phase 4: Rerun and compare against the current build
- [ ] Snapshot the current outputs into scratch tables (`fwapg.pcic14_before_crosswalk`, `fwapg.pcic14_before_monthly`).
- [ ] Rerun `./pcic_crosswalk.sh` in the background, logging to `data/run14.log` (about 30 min; do not run the main-flow tree job at the same time). QA must pass, including both new tests.
- [ ] Compare against the snapshot:
  - the crosswalk should differ only at the 6 outlets (segment and codes);
  - list the segments whose flow changed, which should be junction-start segments and the 6 outlets' segments;
  - derive the count of junctions where a tributary's step moved down, replacing the issue's unverified 1,464 of 5,892;
  - totals at river mouths should be unchanged.
- [ ] `./qa_gauges.sh` against 494 of 538 within 10%, and update the README numbers that move.
- [ ] Drop the snapshot tables. Record the measurements in `findings.md`, with the log prefix `data/run14*` as evidence.

## Validation

- [ ] QA passes (`sql/qa.sql`, all `t`), and both new tests went `f` -> `t` across the fix
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
