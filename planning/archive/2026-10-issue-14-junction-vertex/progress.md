# Progress — PCIC crosswalk: flow and placement at a tributary junction's vertex (#14)

## Session 2026-10-11

- Plan-mode exploration; phases approved by user ("go all phases to pr")
- Created branch `14-pcic-crosswalk-flow-and-placement-at-a` off `newgraph`
- Scaffolded PWF baseline from issue #14 with approved phases
- Next: start Phase 1
- Phase 1 (c82a16e): two QA tests, both `f` on the #13 build
- Phases 2-3 (88a60d0): strict junction test in 07; step>0 rules in 06/07; the vertex move in 06. Plan corrected: 94 vertex outlets have a line joining at their measure, not only the 6
- Plan review (7dbda7e, review-1.md); intermediate run `data/run14.log`, all QA t
- Phase 3b (5020767): anchor match, 1 mm landing, `candidate_rank`, FWA-child invariant and junction ceiling QA
- `/code-check branch`, 3 rounds (1fb1071, df81e20, eae70af): mouths and stacked outlets stop the job; a 1 mm tolerance on step>0 (a 2,130 ha tributary had no flow, pre-existing); landing below the next segment's start, not `upstream_route_measure`. Ended by enumeration
- Final run `data/run14b.log` on eae70af: 15/15 QA; gauges unchanged (494/538); fingerprint in findings
- Answered wet#58 on which build to score: #14's, after merge
- Next: archive, PR into newgraph
