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
