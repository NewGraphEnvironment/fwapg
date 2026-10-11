# Findings — Run blue line paths, PCIC crosswalk and main-flow tree end to end (#13)

## Issue context

**If we do it:** the three extras jobs on `newgraph` (`blue_line_paths`, `pcic_crosswalk`, `mainflow_tree`) have each run end to end in their committed form, and are ready to be cut into upstream PRs. **If we don't:** they go upstream having been read but never run as scripts. In #2 every SQL file ran, but piece by piece, so the scripts' shell parts never did. `pcic_crosswalk.sh` has not run in full since the blue line paths moved out of it.

## What was not run (#2, PR #11)

- `mainflow_tree.sh` and `blue_line_paths.sh` as scripts: the relative `cd`, the call from one script into the other, the `|t` QA guards, `\copy ... TO 'file'` + `gzip`, and the `psql -1` wrapper (added after the only paths build).
- `pcic_crosswalk.sh` steps 1-2 and 5 (export, cleanup) and its new call to `../blue_line_paths/blue_line_paths.sh`. Steps 3-5 were rerun by hand and matched the previous build exactly.
- SSNbler on LSKE, BULK and FRAN (29-30k lines, about 55-60 GB at the measured growth), and on any whole basin (SSNbler's parallel path above 46,340 lines is unmeasured).

## What it needs

A full provincial fwapg (`fwa_stream_networks_sp`, `fwa_streams_watersheds_lut`, `fwa_watersheds_upstream_area`, `fwa_bcboundary`) and, for the SSNbler runs, enough memory for one 30k-line group: about 60 GB free for R at the growth measured in #2 (39 GB at 24,000 lines). Measured runtimes so far: blue line paths about 35 min, topology QA about 35 min.

## Plan

1. Merge PR #11 into `newgraph` and check it out on the host.
2. Reuse an existing PCIC download cache (`extras/pcic_crosswalk/data/`, gitignored) rather than downloading again.
3. Before running, two changes to `extras/mainflow_tree`:
   - `sql/qa_topology.sql`: build the BC outline once (`ST_Union` of `fwa_bcboundary`, then subdivided and indexed) and test each mouth against it, instead of unioning the boundary pieces once per mouth. That per-mouth test is about 34 of the QA's 35 min. The result must be the same 23 `no_parent` mouths.
   - The SSNbler run scripts: a memory watchdog on the R process itself, and one run at a time.
4. Run, with `DATABASE_URL` pointing at the database:
   - `extras/pcic_crosswalk/pcic_crosswalk.sh`. It rebuilds the paths through `blue_line_paths.sh`. Compare `pcic_fwa_crosswalk` and `fwa_stream_networks_discharge_monthly` with the #11 build (48,716 rows; 40,524,612 rows, sum(round(q_m3s,6)) = 178169881.209890). QA 10/10; blue line paths QA 3/3.
   - `extras/mainflow_tree/mainflow_tree.sh`. Expect 4,510,368 segments and QA 10/10 (0 splits, 8 cut-offs, 473 dead ends, 23 `no_parent`).
   - The two jobs never at the same time: both rebuild the shared paths.
5. SSNbler, one group at a time: LSKE, BULK and FRAN whole, and the USKE and MSKE spots again. Then, if whole-basin checks are wanted, a ladder (50k, 100k, the Nechako at 210k lines) with memory sampled, so the memory needed is measured rather than extrapolated.
6. Fix whatever breaks, record runtimes and peak memory in the READMEs, then cut upstream branches off `upstream/main` (new directories, so `git checkout newgraph -- <dirs>`, then strip the NGE-only parts: `fresh-bc` lines, our issue references, `planning/`, `CLAUDE.md`). Upstream PRs are drafted, not posted, until approved.

## Done when

- [ ] All three scripts have run end to end in their committed form, with outputs matching the #11 build
- [ ] Topology QA runtime measured after the BC-outline change
- [ ] SSNbler results for LSKE, BULK and FRAN recorded in `extras/mainflow_tree/README.md`
- [ ] Upstream branches drafted


## Pre-flight (2026-10-10)

- Run machine FWA source matches the #11 build machine: 4,907,441 segments, sum(length_metre) 1,954,935,915,
  28,001 `fwa_bcboundary` rows, 4,538,224 `fwa_streams_watersheds_lut` rows. #11 numbers are a valid reference.
- No outputs on the run machine yet (`fwapg.blk_paths`, `pcic_fwa_crosswalk`, `fwa_stream_networks_mainflow_tree` absent).
- `db/` and `load.sh` unchanged since `8b3904e` (the run machine's load), so no reload needed.
- Tools present: psql, jq, ogr2ogr, cdo, ncdump, Rscript, sf 1.1.2. SSNbler not installed (build machine has 1.1.2).
- Docker VM reports ~118 GB: R and Postgres share RAM, so the SSNbler cap comes from measured free memory.
- The #2 watchdog (gitignored `serial.sh`) sampled only the R master PID; the parallel path forks workers.

## Phase 1 (2026-10-10)

- PCIC cache copied (650 MB with the reference files; 244 monthly batch files).
- References in `extras/*/data/ref_11/` (gitignored): the three #11 exports, `qa_drainage.csv`, `qa_topology.csv`.
  The committed-era `qa_topology.csv` predates the `no_parent` class (8 cut_off + 473 dead_end only), so the full
  504-row QA table (8 / 473 / 23 `no_parent`) was exported from the build machine's `fwapg.mainflow_tree_qa` as
  `qa_topology_db.csv`. Build machine DB counts match the issue: crosswalk 48,716; monthly 40,524,612 rows, sum
  178169881.209890; tree 4,510,368.
- SSNbler 1.1.2 from CRAN (R 4.5.2), the version used in #2.
- Memory at idle: the Docker VM process holds 55.4 GB RSS (its configured ceiling is ~118 GB), other apps ~6 GB.
  So R has about 60 GB now; the cap is re-measured before Phase 5, because the VM can grow during the pipelines.

## Review of the watchdog and BC outline (2026-10-10, `review-watchdog.md`)

Reviewer read 436a4ea and aaa8acc, probing in a copy. Folded in:
- BC outline: equivalent to the per-mouth union in exact arithmetic (fwa_bcboundary parts are the dump of
  one union, interiors disjoint). Subdivision moves the edge by ~1e-10 m where cut lines cross it, so only a
  50 m circle tangent to BC's edge within 1e-10 m could flip. Phase 4 adds the tangency check to make the
  row diff conclusive.
- Watchdog, all fixed: RSS on macOS excludes compressed memory (the Docker VM showed 112 GB footprint, 82 GB
  compressed), so the cap now sums `top`'s footprint; a TERM/HUP to the script left R running unwatched and
  freed the lock, so cleanup now stops R and its workers (TERM, KILL after 10 s); `workRSOCK` matched every R
  cluster on the machine, so ssnbler_check.R now sets `parallel:::setDefaultClusterOptions(outfile=)` and the
  script matches that absolute path (PSOCK workers have ppid 1, confirmed); a failed sample read as 0 and
  disabled the cap, so it now returns ERR and three in a row stop the run (exit 4); stale lock is taken over
  when its pid is gone; a floor on `kern.memorystatus_level` (10%).
- Probe: a dummy master + one tagged worker holding 2 GB sampled at 2,062,336 KB; ERR after exit.

## PCIC crosswalk, first full run (2026-10-10, `extras/pcic_crosswalk/data/run13.log`)

- `pcic_crosswalk.sh` as committed, exit 0, 15:46:58-16:15:34 (28.6 min). Stages (PS4 timestamps): PCIC load
  from cache 13 s; outlets 3.2 min; monthly series from cache 1 s (every batch already reduced); blue line paths
  16.6 min (35 min on the #11 build machine); candidates 32 s; prepare 5 s; placement 3 rounds 15 s; subbasins
  27 s; segments 6.0 min; drainage QA 11 s; QA + report + export + gzip + cleanup 1 min.
- `fwa_stream_networks_discharge_monthly`: identical to #11 (sorted md5), 40,524,612 rows, sum 178169881.209890.
- `pcic_fwa_crosswalk`: 48,716 rows, **2 differ** from #11: subids 5013950 (SMAR) and 5019556 (UARL) placed on
  707670668 / 707720978 instead of 707670667 / 707720975. Same blue line and measure: each probe sits on the vertex
  two segments of one blue line share, so the two are equally near, and `pcic_crosswalk02_candidates.sql` ordered
  by distance with no tie-break (`DISTINCT ON (blue_line_key) ... ORDER BY blue_line_key, ST_Distance`, the
  watershed-key lookup's `ORDER BY ST_Distance LIMIT 1`, and the `LIMIT :num_features` cut). Which segment won
  depended on the plan. Fixed with `linear_feature_id` as the tie-break (lowest id, which #11 happened to pick in
  both cases). The KNN `ORDER BY geom <-> probe LIMIT 100` is left alone: a second sort key would drop the index
  ordering. Monthly flow was unaffected (both choices are the same point).
- `qa_drainage.csv`: the reference CSV (21:47 Oct 8) predates the last `qa_drainage.sql` commit (22:02), so the
  build machine's `fwapg.pcic_qa_drainage` table was exported as `ref_11/qa_drainage_db.csv`. Against it only the
  same two subids differ (edge_type of the chosen segment).
- `diff` in this shell is a wrapper around `git diff`; comparisons use `/usr/bin/diff`.

## PCIC rerun with lowest-id tie-break (2026-10-10, `extras/pcic_crosswalk/data/run13b.log`)

- 16:18:01-16:45:50 (27.8 min), exit 0, QA 13/13 (paths 3, crosswalk 10). Paths 16.2 min.
- Against #11: **449 crosswalk rows differ**, nearly all ties (421 of 422 paired rows have the same measure within
  1 mm). About 1% of outlets sit on a vertex two segments of one blue line share. Monthly: 40,524,600 rows (one
  segment fewer), sum 178168440.449780 (vs 178169881.209890, -0.0008%); qa_drainage one row fewer. Diff kept in
  `extras/pcic_crosswalk/data/run13b_crosswalk.diff`.
- So #11's choice was the KNN index scan's order, not a rule: run 1 matched it on all but 2 only because the two
  machines' indexes were built alike. Lowest id is just as arbitrary.
- **Decision (user, 2026-10-10): upstream segment.** Tie-break `downstream_route_measure DESC` (the segment
  starting at the vertex; FWA measures run [drm, urm)), then `linear_feature_id`. At a tributary junction that is
  the segment above it, which is what a PCIC sub-basin outlet there drains. The `LIMIT :num_features` cut across
  different blue lines keeps `linear_feature_id` (no positional order between lines).

## Main-flow tree, full run (2026-10-10, `extras/mainflow_tree/data/run13.log`)

- `mainflow_tree.sh` as committed, 16:47:18-17:07:35 (20.3 min), exit 0, QA 13/13 (paths 3, tree 10).
  Paths 15.8 min, tree 2.9 min, **topology QA 1.5 min** (was ~35 min), exports 6 s.
- Tree export identical to #11 (4,510,368 rows, sorted md5). `qa_topology.csv` identical to the build machine's
  504-row `fwapg.mainflow_tree_qa` (8 cut_off, 473 dead_end, 23 no_parent).
- Tangency guard for the BC-outline change: of 26,713 orphan mouths, none lies within 1 mm of 50 m from BC's edge;
  the closest is 1.26 m from the threshold, so the old and new tests cannot disagree on any mouth (the buffer's
  polygon approximation sags at most ~0.24 m at 50 m).
- A first attempt at that check compared endpoints with `ST_DWithin` and no usable index; cancelled after 10 min
  with `pg_cancel_backend` and redone with the 1 cm node keys qa_topology.sql uses (40 s).

## Watchdog tests (2026-10-10, `extras/mainflow_tree/data/ssnbler/runs.log`, `test_*`)

- Normal: LKEL (Skeena share) 2,218 lines, 0 node errors, 1 outlet (as in #2), exit 0, peak 0.6 GB, 6 s.
- Guard fires: cap 1 GB on UTRE (Nechako share, 5,533 lines) -> killed at 1.4 GB, exit 3, lock released.
  Without the cap UTRE finished in under 12 s, 0 errors, 2 outlets (as #2), peak 1.4 GB (#2 recorded 3 GB RSS
  on the other machine).
- Signal: TERM to the script during NECR (21k lines) -> R stopped and lock removed within 4 s. (A first attempt
  signalled the `export && ./script` wrapper subshell instead of the script; the script correctly kept watching.)

## SSNbler groups (2026-10-10, `extras/mainflow_tree/data/ssnbler/runs.log`)

`./ssnbler_check.sh 90 <name> <wscode> <group>`, one at a time, cap 90 GB footprint (kernel reported 92% of
memory available with the DB running; 29 GB unused, the VM's 112 GB footprint mostly reclaimable). Peak is top's
footprint, which top prints in whole GB above 10 GB.

| group (basin share) | lines | node errors | outlets | peak | minutes |
|---|---|---|---|---|---|
| USKE (Skeena) | 21,655 | 4 | 1 | 28 GB | 1 |
| MSKE (Skeena) | 24,732 | 4 | 1 | 37 GB | 2 |
| LSKE (Skeena) | 29,266 | 0 | 1 | 52 GB | 2 |
| BULK (Skeena) | 30,046 | 0 | 1 | 52 GB | 2 |
| FRAN (Nechako) | 30,134 | 0 | 2 | 54 GB | 2 |

- USKE and MSKE: the 4 errors (2 Downstream Divergence + 2 Unsnapped Node, all Confluence) are at the two ends of
  239055049 (1.6 cm) and 141013301 (2.9 cm) exactly, as in #2.
- LSKE, BULK, FRAN (never run before): 0 node errors. FRAN's second outlet is the Nechako dead end in FRAN the
  README lists. So all 29 groups holding the Skeena or Nechako (bar the three one-segment shares) are now checked.
- Memory follows #2's growth (27-28 GB at ~22k lines on both machines; ~52 GB at 30k).
- Runtime is minutes, not the hours feared: the serial path is memory-bound, not time-bound.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `diff` printed a git-style diff and `grep -c "^<"` counted 0 | `diff` is a shell wrapper; use `/usr/bin/diff` |
| Endpoint `ST_DWithin` join ran 10 min unindexed | Cancel on the server (`pg_cancel_backend`); join on rounded 1 cm node keys |
