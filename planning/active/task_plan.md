# Task: PCIC crosswalk: build routed flow for a chosen model, scenario, years and time step (1981-2010, CMIP6, weekly) (#25)

**If we do it:** routed flow per FWA segment can be built over 1981–2010, the normals period wet's open water balance uses, and from hydromosaic's CMIP6 runs, through the same crosswalk. It can also be built per week as well as per month. **If we never do:** the monthly table stays 1951–2012 only, so per-segment products mix periods (wet#57 states the period per row), and projections need a second pipeline.


## Decisions at the plan gate (2026-10-17)

- **Output: a new `pcic` schema with run columns (folds in #23).** The tables are `pcic.discharge_monthly` and `pcic.discharge_weekly`, keyed `(linear_feature_id, model, scenario, period, month|week)`, plus `pcic.fwa_crosswalk`. A run replaces only its own rows. The existing `whse_basemapping` tables stay loaded until wet moves, so nothing breaks today.
- **Day bins: calendar month-day.** The climatology has 366 bins keyed `(month, day)`, so months reproduce today's `ymonmean` exactly. A week is a fixed run of days in a 365-day year: week 1 is Jan 1–7, and week 52 is Dec 24–31 (8 days). Feb 29 folds into week 9, which holds Feb 26–Mar 4.
- **Daily output: sub-basin daily climatology plus per-segment weights.** Flow on a segment for any day, week or window is `greatest(sum(q_acc of upstream_subids) + q_local * share, 0)` over the period's mean sub-basin flows. This reproduces the monthly and weekly tables exactly.


## Phase 1: Probes before code
- [x] Measure how `cdo` (2.6.0) `ydaymean` bins leap years. Run it on a synthetic daily file (value = month*100 + day, 1951–2012) and record whether its bins are month-day or day-of-year. If they are day-of-year, use `del29feb` + `ydaymean`, with Feb 29 taken separately by `selmonth,2 -selday,29 -timmean`. Record the result in findings.md.
- [x] Probe hydromosaic's bulk endpoint with a CMIP6 request for one small batch (`model: "CNRM-ESM2-1"`, `scenario: "historical, ssp245"`). Record the accepted strings, the file size and time per outlet, and whether that batch's missing outlets match PNWNAmet's.
- [x] Write the week bins and the weights formula into findings.md as the spec the code is tested against.

## Phase 2: Fetch keeps a daily climatology, with the run as parameters
- [x] Add the parameters `MODEL` (default `PNWNAmet`), `SCENARIO` (`historical`) and `YEARS` (`1951/2012`), as environment overrides at the top of `pcic_crosswalk.sh`. `PERIOD` (e.g. `1951-2012`) is derived from `YEARS`. Add `WEEKLY=1` to build the weekly table as well; the monthly table is always built.
- [x] Put the cache in its own directory per run: `data/daily/<model>_<scenario>_<period>/` (the scenario string made safe as a slug). `fetch_batch` writes `subid,month,day,n_days,q_m3s` (366 bins) and still deletes the NetCDF. The `.split` and resume logic and `missing.txt` become per run.
- [x] Load the daily climatology into `fwapg.pcic_outlet_daily (subid, month, day, n_days, q_m3s)`, which replaces `pcic_outlet_monthly`. The `no_series` test in `04_select.sql` reads it.
- [ ] Regression: monthly means derived from the new 1951–2012 daily cache, with `n_days` as weights, match `data/monthly/*.csv` within 1e-6 relative at every `(subid, month)`.

## Phase 3: Weights, then period tables
- [x] Change `06_subbasins.sql` to build `fwapg.pcic_subbasins_daily (subid, month, day, n_days, q_local, q_acc)`. The local-runoff and depth-ordered accumulation logic is unchanged; its key gains `(month, day)` in place of `month`.
- [x] Change `07_segments.sql` to write weights instead of flow: `fwapg.pcic_segment_weights (linear_feature_id, watershed_group_code, subid, share, upstream_subids)`, still per watershed group under `xargs -P 4`. Placement, nearest outlet and share logic stay as they are.
- [x] New `08_periods.sql` (`-v step=month|week`). It averages the sub-basin daily table into period means weighted by `n_days`, then applies the weights with the clamp. It writes the step's staging table (`linear_feature_id, watershed_group_code, <step>, q_m3s`, rounded to 5 decimals as now) and records unclamped-negative counts per period.
- [x] Adapt `qa.sql`, `qa_report.sql` and `qa_drainage.sql` to the daily staging tables, with the monthly table still the one under test. Add weekly tests when `WEEKLY=1`: 52 rows per segment, no negative flow, and outlet segments carrying accumulated flow.
- [x] Add the clamp report to `qa_report.sql`: clamped rows per month and per week, split into all segments and mid-network ones (a segment that is not on an outlet's own segment and has upstream outlets).

## Phase 4: `pcic` schema and per-run export (#23)
- [x] Rename the build's crosswalk to the staging name `fwapg.pcic_fwa_crosswalk` in every job file (04–07, qa*, review_*, `qa_gauges.sql`), so a build no longer writes into `whse_basemapping`.
- [x] Export with a staged swap. Create `pcic` with these tables:
  - `fwa_crosswalk`;
  - `segment_weights`;
  - `subbasin_daily`, with run columns;
  - `discharge_monthly` and `discharge_weekly`, with run columns;
  - `runs (model, scenario, period, weekly, crosswalk_md5, fingerprint, built_at)`.

  Write the run's rows to staging and fingerprint them (rows, segments, `sum(round(q_m3s::numeric, 6))`). Then, in one transaction, delete the run's rows and insert the new ones. Refuse the swap if the crosswalk's md5 differs from the md5 of a run already in `pcic.runs`: the weights and crosswalk are shared between runs. `fwapg.pcic_qa_build` keeps working for `review_build.sh`.
- [x] Write a `.csv.gz` per table and run, e.g. `pcic_discharge_monthly_pnwnamet_historical_1981-2010.csv.gz`. The crosswalk and weights are written once. (Shipped as `pcic.<table>.csv.gz` for the shared tables and `pcic.<table>.<run>.csv.gz` per run, e.g. `pcic.discharge_monthly.pnwnamet_historical_1981-2010.csv.gz`.)
- [ ] Add `load/pcic_*.sql`: create if missing, then for each run file delete that run's rows and `\copy ... HEADER MATCH`, in one transaction. `load.sh` loads the crosswalk, the weights, both PNWNAmet monthly runs and the sub-basin daily. Weekly is not loaded by default: at about 950 MB, the README gives the one-line `psql -f`. The two `whse_basemapping` loads stay as they are until wet moves.
- [x] Give `qa_gauges.sh` and `qa_gauge.sh` the run (model, scenario, period). They read `pcic.discharge_monthly` and take `YEARS` from the period.

## Phase 5: Builds and measurements
- [ ] Rebuild 1951–2012 PNWNAmet (refetch to the daily cache). The QA must pass, and the monthly run's fingerprint must equal the published one (40,524,444 rows, 3,377,037 segments, 178035348.248310). Allow a stated tolerance only if the measured differences are rounding at the 5th decimal, with the count and the largest difference recorded.
- [ ] Build 1981–2010 PNWNAmet with `WEEKLY=1`. Run the QA and `qa_gauges.sh` over 1981–2010.
- [ ] Measure the routing lag: clamped rows per period, monthly against weekly, on all segments and on mid-network ones, with the worst weeks named (the rising freshet). Record it in findings.md and in a `research/pcic_routed_flow_periods.md` topic file that #28 can cite.
- [ ] Measure the outputs: row counts and `.csv.gz` sizes against the issue's estimates (175M rows and about 950 MB weekly), and the job's runtime per step from `date -u`.

## Phase 6: Publish and hand off
- [ ] Upload the new files to `s3://fresh-bc/fwapg/extras/`, then check that anonymous GETs return 200 and that the sizes match. If auto mode refuses the upload, hand over the bare `aws s3 cp` commands.
- [ ] Update the README: parameters, cache layout, week definition, `pcic` tables, the weights formula with an SQL example for any date window, the clamp measurement, and the CMIP6 probe result. Also update `extras/README.md`, and add the `pcic` schema to `CLAUDE.md`'s load notes.
- [ ] File a wet issue to move its reads (`scripts/pcic_routed_lib.R`, `data-raw/segment_vignette_*.R`) to `pcic.discharge_monthly` with a period filter, and to build wet#70's routed daily from `pcic.subbasin_daily` × `pcic.segment_weights`. File an fwapg follow-up to drop the `whse_basemapping` loads once wet has moved.
- [ ] Edit the bodies of #25 and #23 to match what shipped (CMIP6 parameters supported and probed but not built).

## Validation

- [ ] Tests pass: the Phase 2 regression, Phase 5 fingerprint equality, `qa.sql` all `t` on both builds, and the weekly tests
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

## Out of scope
- Full CMIP6 builds (18 runs; at about 2.4 times PNWNAmet's series length, roughly 80 min of fetch each). The parameters support them, and a report that needs projections runs them.
- Per-segment daily rows (about 1.2B). wet#70 derives them from the weights and the sub-basin daily.
- Moving `extras/discharge`'s older `whse_basemapping.fwa_stream_networks_discharge`. #23 mentions it; it is left for #23's remainder.

