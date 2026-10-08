# Progress — PCIC routed streamflow on FWA streams (#5)

## Session 2026-10-07

- Plan-mode exploration — phases approved by user
- Created branch `5-pcic-routed-streamflow-on-fwa-streams-cr` off `newgraph`
- Scaffolded PWF baseline from issue #5 with approved phases
- Next: start Phase 1

## Session 2026-10-07 (implementation, all phases)

- Phase 1: PCIC API paths corrected (`bbox-server` at host root). Found `POST /hydromosaic/bulk-downloads` (NetCDF, one source domain per request, 422 on mixed); batches per tree, halved on 422. 48,716 outlets (48,261 rivers + 455 lakes), 48,688 with series (28 missing). Monthly 1951-2012 via `cdo ymonmean`. GNU parallel not installed here (moreutils shadows it) — job uses `xargs -P`.
- Phase 2: outlets sit at confluences → snap a probe point ≤100 m up the PCIC segment. Root-up placement with one-level subtree look-ahead + iterative demotion. Tolerance 150 m (p95 snap 13 m).
- Code-check round 1 (8 findings) and round 2 (2 bugs inside the round-1 fix 3, QA could not fire) fixed. Round 2's fix led to measured defects in FWA codes: local codes not monotone along a blue line (Fraser, Stikine), one outside its wscode (cycle), drm compared across blue lines (side channels). Fixes: measure-only same-line comparisons; repaired out-of-order local codes (`fwapg.pcic_localcode_repairs`, 14,326 segments); same-blue-line-first ordering; cycle guard.
- Flow method changed from "PCIC outflow minus FWA children" to "PCIC local runoff injected at placed outlets, accumulated down the FWA tree" — mass-conserving; equals PCIC outflow where networks agree.
- Result (local fresh-db): 36,888 placed; 3,391,444 segments × 12 months; accumulated flow within 5% of PCIC at 97.8% of placed outlets, 99.2% of those > 100 m³/s; all 7 QA tests pass. Gauge 08EE003: FWA area 2315 vs 2319 km²; freshet within 0.87-1.41×, low flows 1.2-1.7× high.
- Next: code-check round 3 (mechanism + enumeration), commit, /planning-archive, PR into `newgraph`.

## Session 2026-10-07 (continued: review rounds 3-5)

- Round 3 named the mechanism: FWA position fields treated as one coordinate system (FWA_Upstream reads ltree order as position). Response: no local-code comparisons at all; `sql/pcic_crosswalk01_paths.sql` builds the downstream path of every blue line (parent line + junction measure), and every position comparison uses it (equi-joins on blue line). SQL files renumbered 00-07.
- User flagged (from fresh `research/fwa_point_snap.md`) that post-filtering FWA_IndexPoint drops whole streams: measured 651 streams lost (mostly unmapped segments, 1425 only 8). `02_candidates` now runs FWA_IndexPoint's search with filters before the per-stream pick. Decided not to change `fwa_indexpoint` here (issue says no changes to fwapg functions); an exclude parameter is a candidate upstream PR.
- Round 4: geometric junction unbounded (Okanagan/Kettle/Similkameen put on the Columbia in BC). Fixed: touch within 1 m or no path. Round 5: that fix orphaned 17,200 braids (Kitsumkalum) and code junctions ignored side-channel entry (Birkenhead). Fixed with attachment rounds and deferred code junctions.
- Segment-boundary ties: same-line comparisons by (segment start, measure).
- Upload destination: `s3://fresh-bc/fwapg/` (NGE bucket), not bchamp.
- Result: 36,474 placed; 3,364,206 segments × 12; within 5% of PCIC at 99.1% of placed outlets (99.9% > 100 m3/s); 9/9 QA tests pass; Columbia and Birkenhead equal PCIC; Kitsumkalum has flow.
- Review cost: 5 rounds (round 2 and 4 and 5 each found defects inside the previous fixes). Round-5 fixes verified by measurement and new QA tests, not yet by a 6th reviewer.
- Not yet run: the export/drop step of the script end to end.

## Session 2026-10-08 (review round 6)

- Round 6 (focused on the round-5 fix in `01_paths`): Birkenhead, Columbia, Kitsumkalum right; no deferred tributary enters upstream; no wrong-neighbour round edges. Two findings, both fixed:
  - acyclicity argument false in principle (a main stem could take a same-code round edge to its own braid) → round edges at the same code only from side channels; header invariant restated.
  - 1,888 side channels with no path though their main stem has one (Seton side channel 355995374 cut off Cayoosh Creek: 49 broken outlets, 0 of 7,560 segments with flow) → step 5 side-channel fallback onto own main stem (local-code equality, else nearest point within 1 km), then rounds again. QA test added.
- Result: 36,527 placed; 3,375,280 segments; 99.1% within 5% of PCIC (99.9% > 100 m3/s); side channels without a path 232 of 74,431; Cayoosh 7,498 of 7,560 segments with flow; 10/10 QA tests pass.
- Export run end to end through the script's step 5 (2.5 min): QA 10/10, pcic_fwa_crosswalk.csv.gz (48,716 rows, 1.7 MB), fwa_stream_networks_discharge_monthly.csv.gz (40,503,360 rows, 217 MB); staging tables and function dropped. Not uploaded (destination s3://fresh-bc/fwapg/).
