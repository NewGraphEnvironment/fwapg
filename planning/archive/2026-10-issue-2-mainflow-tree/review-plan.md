# Plan review (Plan agent, 2026-10-09) — summary and disposition

Reviewer emulated the tree province-wide from `fwapg.pcic_blk_parents` (all edge types).

| # | finding | disposition |
|---|---|---|
| 1 | strict `drm < m` keeps the segment above the entry on 2,846 side channels (junction float above node drm by up to 1.5e-4 m): 366 splits | already in `mainflow_tree.sql` (`< top_measure - 0.01`) |
| 2 | 6 real splits: entry within 1 m of a side channel's top, so the kept part reaches its departure node (KNIG 360244455, NECL 360239146, GRAI 360245909, UNAR 360245821, UHAF 359022306, COWN 354088507) | measure, then rule or overrides |
| 3 | 98 cut-offs; 21 are touches with gap <= 1 m (rule picked the main stem 0.94 m away over a 1 m side channel, e.g. 356187476 / 355995829), not FWA gaps | node-based repair candidate; measure |
| 4 | `blk_touches` is temporary | only matters for a touch-based repair |
| 5 | 6010 excluded from parents, included in tree (35 main-flow lines start with 6010) | province-wide cut-off test covers it; document |
| 6 | prototype per group, 1425 excluded | QA is province-wide, all edge types |
| 7 | `wscode <@ 400` is 15 groups (272,621 segments); `<@ 100.567134` is 20 groups | SSNbler subset uses the issue's groups and the code |
| 8 | "one outlet" fails by construction where a basin holds a cut-off | acceptance: outlets = 1 + cut-offs in the subset |
| 9 | cut-off ceiling fails toward pass on an empty tree or broken snapping | non-vacuity tests |
| 10 | 2 side-channel junctions > 1 m inside a segment | list in findings |
| 11 | 26-connector test exercises reattachment for only 2 | accepted (the issue's list) |
| — | rename leftovers in pcic_crosswalk.sh, READMEs, comments | already done in the working tree |
