# Progress — fwa_indexpoint(): one tie rule and measure method (#41)

## Session 2026-10-24

- Plan-mode exploration, then four gate decisions answered and the phases approved by the user
- Created branch `41-fwa-indexpoint-one-tie-rule-and-measure` off `39-indexpoint-tiebreak` (5579fd5); #40 is unmerged and carries #39's archive
- Scaffolded the PWF baseline from issue #41 with the approved phases
- Next: start Phase 1
- Phase 1: worktree of `indexpoint-tiebreak` at d955688; scratch point sets and baseline (findings.md). FISS load still to do
- Plan review delivered; verdicts in `review-plan.md` (B1 and A1 refuted by probe, the rest folded into task_plan.md)
- User asked mid-run for tests that cover the refactor's premises; added to Phase 3
- Found mid-run: the geometry-M measure makes a stream's head unlocatable in `FWA_LocateAlong`. The user chose to give `FWA_LocateAlong` `FWA_WatershedAtMeasure`'s selection rule (decision 5)

## Session 2026-10-25 (UTC; continues the 2026-10-24 Vancouver session)

- Phases 2-5 written in the upstream worktree (uncommitted until Phase 7's code-check): migration (fwa_indexpoint filters, geometry-M measure, XYZM point, `ST_ClosestPoint` before `ST_LineLocatePoint`; `FWA_LocateAlong` stream-head rule, both schemas), 16 new test cases, channel_width onto fwa_indexpoint, docs
- Defect found by the channel_width run: a MultiPoint input errored. The plan review's B1 had it right, and my `count(*)` probe was wrong. Regression case first, then the fix
- Phase 6 verification: 26/26 tests, each of 8 one-change reverts red, comparisons in findings.md
- Research: `research/fwa_position_codes.md` gains the measure-method and stream-head sections
- Next: `/code-check` on the upstream diff, then commit there
- `/code-check` round 1 (04:53-05:05Z): one fragile finding, two new tests that put the function in FROM and could not print `f`. Swept all new cases, and six of them had the shape: all wrapped, and the defaults case now also asserts a non-empty result. Docs head sentence narrowed; `docs/01_usage.md` example regenerated. 26/26, each revert red (formula and upper-bound reverts now also caught by the head round trip)
- `/code-check` round 2 (05:06-05:16Z): two real defects, both reproduced. (1) Stream heads in the nine other strict-upper-bound functions; the user chose the same rule in all nine (decision 6). (2) A watershed-group boundary point failed `fwa_indexpoint`; fixed with EXISTS, regression case first
- Decision 6 built from the deployed definitions. Verification found that dropping the upper bound outright let the traces answer for a measure past their table's last segment; every selection is now closed at the top. 54/54 tests, 13 reverts each red. Final-body comparison running
- `/code-check` round 3 (15:36-15:51Z): `FWA_SliceWatershedAtPoint` fraction (clamped) and an untested border head clause (test added), both inside the reach of round 2's fix. The loop ended on a mechanical enumeration: 16 consumers, 12 covered, 4 interval functions out of reach; 1 producer, replaced. 56/56, 15 reverts each red
