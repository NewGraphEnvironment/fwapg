# Progress — Main-flow tree: a dendritic stream network computed from FWA (#2)

## Session 2026-10-09

- Plan-mode exploration; prototype on 14 groups (findings.md); phases approved by user ("go all phases to pr")
- Gate decisions: shared blue-line paths job; tree as a lookup table via an extras job
- Created branch `2-main-flow-tree-a-dendritic-stream-networ` off newgraph
- Scaffolded PWF baseline from issue #2 with approved phases
- Next: start Phase 1
- Phase 1: moved blue line parents/paths to `extras/blue_line_paths` (`fwapg.blk_parents`, `blk_paths`, `blk_on_or_upstream`); its 3 path tests moved from PCIC's qa.sql
  - verified: new parents/paths identical to the staged PCIC copy (1,570,499 lines, 0 differ); PCIC rerun from step 3 identical to the pre-refactor build (48,716 crosswalk rows 0 differ; 40,524,612 monthly rows, max |dq| 0); PCIC QA 10/10
  - paths build measured at ~35 min (touches step ~1.2 ms/line), not the 4-6 min the research note said; corrected
