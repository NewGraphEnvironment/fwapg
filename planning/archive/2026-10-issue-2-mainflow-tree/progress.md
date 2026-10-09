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

## Session 2026-10-09 (after restarts)

- Two machine restarts (~16:07 and ~16:50 UTC) wiped the scratchpad and stopped background work; review round 1 (spawned 16:41) never wrote its file, so it is re-run as round 1b (19:57); not recorded as clean
- SSNbler per watershed group (extras/mainflow_tree/data/ssnbler/, gitignored): before the second restart 16 of 18 Nechako groups completed, all 0 node errors (outlets 1-3 per group: the group's exit plus any dead ends); TABR (one segment) fails inside SSNbler's left_join; resuming FRAN, UNRS and the 13 Skeena groups other than KLUM
- Review checklist (full soul code-check conventions, 637 KB) kept at extras/mainflow_tree/data/review-checklist.md, not committed
- Code-check round 1 (1b): 1 bug (stale node_errors.gpkg), 2 fragile (README outlet claim; shared tables rebuilt non-atomically) -> fixed (8826357, f3230fd)
- SSNbler serial, all groups <= 24,732 lines, fixed script: 24 of 26 groups 0 node errors; USKE and MSKE one spot each at a 1.6 / 2.9 cm main-flow segment (geometry a plain chain), unchanged at topo_tolerance 1 m and 1 cm; LSKE/BULK/FRAN (29-30k lines, ~60 GB) not run; whole basins by SQL: Skeena 1 outlet, Nechako 8 (mouth + 7 dead ends)
- Code-check round 2: 0 bugs, 3 fragile, one inside a round-1 fix (my SSNbler rounding comment: 0 -> 10 m, not 1 m; snap_tolerance is also the join distance) -> fixed; PCIC README warning; research path stats from the table (17 / 4.18)
- Code-check round 3 (enumeration of ~70 claims about SSNbler, psql and the data): mechanism "a measured count carrying an inferred label". Fixed: cut-offs are `followed` segments, not reattached; 16 reattached side channels with no parent had no QA class (new `no_parent`, ceiling 16; 10/10 tests pass); Nechako outlets = mouth + 6 dead ends + 1 no-parent; per-group outlets (13 groups exit by two streams, verified); 360216952 is in LSKE, so SSNbler was run on the tree within 5 km of it (783 lines: 0 errors inside the window, 5 converging nodes all where the tree continues outside it); junction_gap_m up to 1 m on a touch; `>= 46,340`; provenance (scripts not run end to end); SSNbler tolerance comment
- Code-check round 4 (round-3 fixes, claims checked by query): 3 more label errors of the same mechanism (4 of 16 no-parent side channels end on the BC border; a mid-basin main-flow outlet, SLOC 380887813, sat among the "leaves BC/sea" outlets; UEUT's third outlet is no-parent, not a dead end) and a segment-level test that should be line-level
- Ended by enumeration: every tree segment whose water continues nowhere in the tree (8 cut-offs + 27,186 mouths touching nothing) classified by measured attributes: 473 dead ends (parent), 26,690 mouths with no parent within 50 m of BC's edge, 23 with no parent inside BC (`no_parent`, 11 main-flow + 12 side channels, ceiling 23; replaces the side-channel-only kind). 10/10 tests pass; every outlet sentence in the README and research note restated from these class counts. Topology QA now ~34 min (BC-edge test)
