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

## Errors Encountered

| Error | Resolution |
|-------|------------|
