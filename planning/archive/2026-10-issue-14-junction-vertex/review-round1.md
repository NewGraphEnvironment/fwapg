# Code-check round 1, #14 (branch diff, planning/ excluded)

Reviewer: subagent, 2026-10-11. Read in full: 06, 07, qa.sql, 02, 03, 04, 05, README diff,
pcic_crosswalk.sh, blue_line_paths.sql. Probed against the read-only build (TEMP tables only).

## Verified (no finding)

- The 06 move, run against the pre-branch crosswalk (`fwapg.pcic14_before_crosswalk`, probe
  distance dropped since `fwapg.pcic_outlets` is gone), selects exactly 6 outlets: 2007294,
  4000204, 4000212, 5014089 (gap move, 43.8 m, candidate_rank cleared), 9001132, 12007835. All
  land 1 mm under the upper end of the segment below the vertex. 141 ms.
- No other placed outlet sits within 1 cm of any of the 6 vertices on the same blue line, so
  none of the moves reverses an outlet against its PCIC anchor in this build.
- All 7 pre-branch child/parent pairs that break the new QA invariant ("joins >= 1 mm above
  the parent's segment start") are children of those 6 outlets, and none is at a line mouth.
- The four new QA tests pass on the current build (8.7 s for the junction-ceiling test, the
  rest well under 1 s). With the tables swapped to `pcic14_before_crosswalk` and
  `pcic14_before_monthly`, all four return f. None of them passes vacuously: the tests guard on
  `count(*) > 0`, `count(*) > 10000` or `coalesce(..., false)`.
- In 06 (parent) and 07 (segment owner), the step>0 rules are the same predicate in the same
  order. The 07 share join (`u.measure >= s.drm + 0.001`) accepts every pair the 06 rule
  produces (`o.seg_measure < J - 0.001`). So the segment an outlet sits on still carries its
  q_acc, and the existing first QA test still holds there.
- A NULL candidate_rank is harmless downstream: qa_report and qa_drainage only filter on
  `candidate_rank > 1`.

## Findings

Neither finding has an instance in the current build. Both are blind spots in the new guard,
and the branch's rules turn each one into wrong flow without any QA test failing.

- **[fragile]** extras/pcic_crosswalk/sql/pcic_crosswalk06_subbasins.sql:130 (also 07:76) and
  qa.sql test "no placed outlet sits above a confluence..." (`s.downstream_route_measure > 0`).
  Take an outlet x placed at its line's mouth (segment start 0, x.drm about 0), with a placed
  PCIC child c on a line T that joins x's line at measure 0. Before the branch, c's FWA parent
  was x (`o.drm <= J`, 0 <= 0). Now `o.seg_measure < J - 0.001` (0 < -0.001) skips x. The move
  cannot help, because it needs a segment below and excludes `s.drm > 0`. So c's flow goes to
  the next line on its path, or becomes a root at the sea, and x's accumulated flow and segment
  flow fall short by c's.
  - Nothing catches it. QA test 1 exempts measure 0, and QA test 2 passes because c's new
    parent is lower.
  - Measured: 2 placed outlets sit at a measure-0 mouth with lines joining there (7000406 GRAI,
    8002298 KITL). Neither joining line has a placed outlet, so this matches the accepted
    "13 segments" case for segments, and there are 0 outlets affected today.
  - Still worth a QA line: drop the `> 0` exemption from test 1 and let it fail (or count) at
    mouths. Alternatively, keep `<=` for step>0 when J < 0.001, the way the measure-0 lines are
    already treated as a documented exception.

- **[fragile]** extras/pcic_crosswalk/sql/pcic_crosswalk06_subbasins.sql:57-58. The move fires
  only for x with a placed descendant on another blue line that is anchored to x itself. Suppose
  x's PCIC parent a is stacked on the same vertex J on the same blue line (04 allows equal
  measures through `blk_on_or_upstream`'s `>=`).
  - Then x moves 1 mm below a. The step-0 tuple order makes x the FWA parent of a, the reverse
    of PCIC: a's accumulated flow loses x's subtree, and a's segment publishes it short.
  - The mirror case is the same: if c is anchored to a stacked child y at J instead of to x,
    y moves below x.
  - Neither a nor x then meets test 1's predicate, since a has no other-line descendant
    anchored to it, so no test reports it.
  - Measured 0 stacked outlets at the 6 vertices in this build. The same class as the accepted
    "move passes a junction carrying placed outlets", but at the vertex itself. A cheap guard:
    count placed same-line outlets within 1 mm of a moved outlet's old measure, and fail on any.
