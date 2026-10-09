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
- Phase 2: `extras/mainflow_tree` (build, topology QA, 8 tests, overrides.csv). Tests failed before the build (relations absent), then 2 failed on the first build (7 split nodes; side-channel test assumed the issue's per-tributary extent was the kept top).
  - rule additions after measuring (and the plan review, `review-plan.md`): no reattachment for a line whose mouth is on a main-flow node; follow cut-offs down while there is one way down; override for the Beaver River's two main lines. Column `reattached boolean` became `source text` (mainflow/reattached/followed/override) so followed segments are visible.
  - province-wide: 4,510,368 segments, 0 splits, 8 cut-offs (all at braid nodes with two ways down); 8/8 tests pass; build ~1 min, topology QA ~30 s
  - run as the script's steps through `docker exec` (no DATABASE_URL credentials in this session), not `mainflow_tree.sh` end to end
- Dead ends added to the topology QA: a tree mouth that touches no network segment on a line the paths give a parent. 473 province-wide (354 main stems off their code junction, 119 fallback side channels); ceiling test; 9/9 tests pass. Found because the Nechako basin had 8 outlets (its mouth + 7 reservoir-group side channels) while the cut-off count said 0 there.
- SSNbler whole-basin run (8 PSOCK workers, ~14 GB, 20+ min, machine compressing 26 GB) stopped; switched to per watershed group (serial, under SSNbler's 46,340-line parallel threshold). KLUM: 24,732 lines, 0 node errors, 1 outlet, 3 min.
- Session restart wiped the scratchpad (SSNbler exports and logs); rerunning into `extras/mainflow_tree/data/ssnbler/` (gitignored)
