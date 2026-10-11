# Code-check round 2 (#14): review of the whole branch diff, focused on 1fb1071

Reviewer: subagent, 2026-10-11. All probes are read-only: TEMP copies of
`fwapg.pcic14_before_crosswalk`, which holds this branch's placement because 02-05
place outlets the same way as before. Probe SQL is in the session scratchpad (`r2/t1-t9.sql`).

## Findings

- **[bug, already in the pre-branch build, on a line this branch edited]**
  `sql/pcic_crosswalk07_segments.sql:76` and `sql/pcic_crosswalk06_subbasins.sql:140`.
  The step > 0 predicate `o.downstream_route_measure <= st.measure` has no tolerance. The new
  `o.seg_measure < st.measure - 0.001` clause already decides which side of the junction an
  outlet is on, so this exact comparison now only adds float noise. In this placement, three
  outlets sit at the upper end of the segment below a junction and measure 1e-14 to 1e-10
  ABOVE the junction: 5012573, 5017485 and 206006820. Each one's tributary skips it and goes
  to the next outlet down. Measured effect: tributary 356567538 (2,130 ha, joining at 5012573)
  has **0 m3/s in all 12 months**, in both the pre-branch build and the intermediate build
  (lfid 706874830). Its segments go to 5012569, whose local area is -28,693 ha, so
  their share is 0. Tributary 356555092 (683 ha) gets a share of 5017489's local area
  (769 ha) where it should get a share of 5017485's. No QA test sees either case. Fix:
  `o.downstream_route_measure <= st.measure + 0.001` in both files, so they stay in step and
  test 2 is unaffected. The same change also fixes the next finding.

- **[fragile]** `sql/pcic_crosswalk06_subbasins.sql:52`. `least(x.downstream_route_measure,
  b.upstream_route_measure - 0.001)` does not always land 1 mm inside the segment. When b's
  upper end overlaps s's start by more than 1 mm, `least()` returns `x.drm`, which is
  exactly the junction measure. That overlap occurs at 2.2% of FWA segment boundaries
  province-wide (68,524 of 3,124,151 within 1 cm; up to 4.4 mm). In the 6 moves of this
  build, 4000212 lands only 0.63 mm below and 9001132 only 0.72 mm below. x is then
  c's FWA parent only if `x.drm <= u.measure` holds at float noise. Junction measures sit
  below their segment start at 19,415 of 1.57M paths (almost all by under 0.3 mm). When that
  happens, c is silently parented around the moved outlet. Test 1 passes because x has moved
  off the vertex, and test 2 passes because c's new parent is valid. The probability per move
  is low (about 2e-4), but the comment's claim ("so that which junctions it sits below does
  not rest on float noise") is false in exactly this case. Fix: `least(x.drm, b.urm) - 0.001`,
  or the tolerance in the finding above.

- **[fragile, a gap inside round-1 fix (b)]** `sql/pcic_crosswalk06_subbasins.sql:84-90`. The
  stacked-outlet `NOT EXISTS` looks only within 1 mm of the outlet's OLD position. The move
  lands at `b.upstream_route_measure - 0.001`, which can be up to 100 m lower when unusable
  segments are skipped. Any placed outlet y on b between the landing and b's top is then
  overtaken, and their order on the FWA is reversed, which is the outcome fix (b) exists to
  prevent. Such a y is likely in a skip, not a coincidence: 02 excludes unusable segments
  before the per-line pick, so every probe nearer to the lower half of the skipped stretch
  snaps to b's top vertex exactly. Skips are common. One of the 6 moves today skips one
  (5014089, 43.8 m), and 26 of the 168 placed outlets on a segment-start vertex have an
  unusable next segment. Nothing is overtaken today: the landing bands of all 6 are empty.
  When it happens, the main stem above and c parent to y, then y to x. x's and y's local
  runoff are put on the wrong side of each other, and if y is x's PCIC anchor, the chain is
  inverted. Neither QA test 1 nor test 2 sees it. Fix: test the band the outlet crosses,
  `y.downstream_route_measure >= least(x.drm, b.urm) - 0.001 AND y.downstream_route_measure
  < x.drm + 0.001` (b is available inside the subquery).

## Checked and clean

- **Dropping the `measure > 0` exemption from QA test 1 (fix a) does not fail on a real
  build.** On this placement, test 1 matches 7 rows across 6 outlets (2007294, 4000204,
  4000212, 5014089, 9001132, 12007835). None is at a line mouth, none is stacked, and every
  one has a direct PCIC child joining exactly at its vertex. After the simulated move, all
  6 have a target and test 1 returns t.
- **The stacked check (fix b) skips nothing today:** every hit has a stack count of 0.
- **The new fwa_parent rule, run after the simulated move,** matches the pre-branch parents
  and the intermediate build's parents exactly (0 changed of 37,667). All 11 anchored
  children of the 6 moved outlets keep the moved outlet as their parent. The tree has no
  cycle (37,667 of 37,667 reached), and test 2 has 0 failures over 10,092 pairs. Only these 6
  outlets have a placed outlet joining at their vertex, so the 06 rule change has no effect on
  parents today. Its effect is in 07's segment ownership.
- **Test 2 can fail:** the old `<=` rule, with x left on the vertex, makes c a child of x at
  its own segment start, so `ok` is false.
- **Test 3 and test 4 cannot pass vacuously.** Test 3 is `coalesce(..., false)` on fixed ids,
  and test 4 requires `count(*) > 10000`.
- **The `UPDATE ... FROM (subquery)` aliasing is correct.** The inner `x` shadows the target,
  and `SET` reads the old row for `candidate_rank`.
- **The move's segment filter matches 02's candidate filter,** so no placed outlet can sit on
  a skipped segment.
