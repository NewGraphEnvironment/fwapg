# Plan review 1 (#14): Plan agent, 2026-10-11

The reviewer read both the plan and the as-built 88a60d0 (Phases 2 and 3 had landed while it worked), and measured on the #13 build. It changed nothing persistent.

## Blockers in the plan text (all fixed in 88a60d0)
- **B1.** "Stays put; the Phase 1 test fails on it" contradicted "QA must pass" at 5014089. The segment below it (707098172, 43.8 m) is not in `fwa_streams_watersheds_lut`, and its child 5014088 (blue line 356563710) joins exactly at 5014089's segment start. Left in place, it would also fail "outlet segments carry accumulated flow". The as-built code moves it to the nearest usable segment within 100 m (707098394). The Phase 3 text was stale (now rewritten).
- **B2.** A plain `>` is not enough. 19,860 junctions sit 0-1 mm above a segment start (touch 15,274, touch_round 4,534, side_fallback 54): float noise from `ST_LineLocatePoint` (`blue_line_paths.sql:112,169`). 118 of them (tributary > 1 m3/s in June) stepped on the upper segment. As built, the test is `>= drm + 0.001`. Code junctions (1,467,190) are always exact starts (`blue_line_paths.sql:140`). The findings figure "1,568,353 exactly" was wrong (corrected).
- **B3.** The step>0 rules (06:126, 07:76) must agree with the passing rule. Otherwise a vertex outlet's own segment misses its child's flow. As built, both use `o.drm <= M AND o.seg_measure < M - 0.001`.

## Gaps
- **G1.** Match the child by `c.anchor_subid = x.subid`, not `dowsubid`: a placed descendant through an unplaced child is in x's flow too. It returns the same 7 children today.
- **G2.** Nothing directly tests the invariant: every placed outlet's FWA child on another line joins at least 1 mm above the parent's segment start, mouths included.
- **G3.** 556 junctions are at measure 0 (548 side_fallback). With the strict rule, water joining P at 0 passes no segment of P. 10 such lines carry > 1 m3/s in June; on the #13 build no FWA child joined its parent at 0. Expect diffs on those main stems' lowest segments.
- **G4.** The move lands on `b.upstream_route_measure`, which is itself a vertex. At 5014089, side channel 356367323 joins there (15307.5603), and the moved outlet at 15307.5611 is above it only by float noise.
- **G5.** Columns: `linear_feature_id`, `localcode_ltree`, the measure (< 1 mm for 5 outlets, 43.8 m for 5014089) and `distance_to_stream` (5014089 only) change. `candidate_rank` goes stale for 5014089. Without `least()`, 3 of the 6 measures would fall outside their segment. No PCIC sibling joins at any of the 6 vertices.

## Assumptions to verify after the rerun
- **S1.** Shares at junction-start segments. Before the fix, the upper segment's share was (A_upper - A_trib)/local, clamped to 0; it is now positive. At touch, side-channel or double-line junctions the lookup may give the upper segment the tributary's area, and its share can then reach the clamp. Count the junction-start segments whose flow is above the segment below's.
- **S2.** 9001132 moves onto 710207545, which already holds its FWA parent 9001135. 9001135's local area becomes 0, and its `q_local` then shows on no segment. This is an existing pattern.

## Compare phase
- **O1.** Crosswalk: exactly 6 rows change, and `fwa_parent_subid` should be identical everywhere (assert it). Segment flow also changes in the 6 sub-basins and their parents', on the 89 tributary lines with no placed outlets (moved to the sub-basin below), on the lowest segments of lines joined at measure 0, and at side_fallback junctions.
- **O2.** The staging tables are dropped on success, so compare at segment level. For totals, use the root outlets' segments (`fwa_parent_subid IS NULL`), not mouth segments.
- **O3.** No heavy ad-hoc queries while the job runs.

## Acceptance
- QA test 1 is well formed: it fails on #13 and passes once all 6 have moved. It checks position, not flow, so pair it with G2.
- QA test 2 fails on #13 and should pass, since the tributary's outlets join at the exact start of 701317184, leaving about 14 m3/s. It covers a single exact junction, not B2's class.
- **Population numbers (#13 build).** These replace the issue's unverified 1,464 of 5,892. Of 20,745 junctions within 1 mm of a segment start whose tributary carries > 1 m3/s in June, 2,720 stepped on the upper segment: 2,547 exact, 118 within 1 mm above, and 55 within 1 mm below. The 55 come from area share at touch junctions with no tributary outlet, so the residual after the fix will not be 0. The definition: in June, q(upper) - q(segment above it) > 0.5 x q(tributary's lowest segment).

## Scope
Leaving `blk_on_or_upstream` unchanged for 04 and 05 is right. One existing case remains: a junction partway along a segment, below an outlet on that segment, still steps one segment too low.
