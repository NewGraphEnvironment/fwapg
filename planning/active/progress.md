# Progress — Fix SSNbler's false topology errors on a fork, PR upstream, re-run the SSNbler check (#16)

## Session 2026-10-10

- Plan-mode exploration; phases approved by user. Decision at the gate: exact difference-based distances
  replace pdist() rather than the issue's origin shift (pdist error measured proportional to coordinate size)
- Created branch `16-fix-ssnbler-s-false-topology-errors-on-a` off `newgraph`
- Scaffolded PWF baseline from issue #16 with approved phases
- Next: start Phase 1

## Session 2026-10-11

- Phase 1: forked to the NewGraphEnvironment user account, cloned, baseline 157 pass; reprex reproduces A and B
- Plan review (Plan agent, `review-plan.md`): 2 blockers (parallel tests unreachable after exact
  distances; workers load the installed package), folded into the plan; fork rebased on upstream `develop`
- Phases 2-3: tests first (failing on 1.1.2), then three fix commits in the fork; 188 pass; MF_streams
  identical before/after; three mutants each caught
- Next: Phase 4 R CMD check
