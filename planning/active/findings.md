# Findings — PCIC crosswalk: build routed flow for a chosen model, scenario, years and time step (#25)

## Issue context

**If we do it:** routed flow per FWA segment can be built over 1981–2010, the normals period wet's open water balance uses, and from hydromosaic's CMIP6 runs, through the same crosswalk. It can also be built per week as well as per month. **If we never do:** the monthly table stays 1951–2012 only, so per-segment products mix periods (wet#57 states the period per row), and projections need a second pipeline.

## Context

`extras/pcic_crosswalk/pcic_crosswalk.sh` asks hydromosaic's bulk endpoint for `model: "PNWNAmet", scenario: "historical", variable: "streamflow"`, and takes monthly means of daily flow over the whole series (1951–2012).

Hydromosaic (`https://beehive.pacificclimate.org/hydromosaic/openapi.json`) serves more on the same `subid` network. At outlet 4008184, `GET /outlets/4008184/timeseries` lists 57 series:

- streamflow from PNWNAmet `historical`, daily, 1950-01-01 to 2012-12-31 (23,011 steps);
- streamflow from 9 CMIP6 GCMs (CNRM-ESM2-1, FGOALS-g3, IPSL-CM6A-LR, MIROC-ES2L, MPI-ESM1-2-HR, MRI-ESM2-0, NorESM2-LM, TaiESM1, UKESM1-0-LL) × `historical, ssp245` and `historical, ssp585`, daily, 1950–2100 (55,152 steps);
- the same for `water_temp` and `DO_sat`.

So the crosswalk (placement, sub-basins, accumulation) carries any of these unchanged. Only the series fetched and the years averaged differ.

**The time step is set in one place.** `pcic_crosswalk.sh` step 2 reduces each batch's daily NetCDF with `cdo ymonmean -selyear,$YEARS` and then deletes the daily file. Everything after that carries a `month` column and does not depend on there being 12 periods:
- `pcic_outlet_monthly`;
- the sub-basin accumulation;
- the per-segment formula in `sql/pcic_crosswalk07_segments.sql`;
- the `(linear_feature_id, month)` key.

So weekly flow needs a different reduction and a re-fetch, not a different pipeline.

## Proposed

- Parameters for model, scenario and the years averaged, defaulting to today's build (PNWNAmet, historical, the whole series).
- A 1981–2010 PNWNAmet build first: wet#57 wants it for one period across sources.
- Output keyed on those parameters (a `model`, `scenario` and `period` column, or one table per run), so builds sit side by side. This fits #23's schema move.
- **A time step parameter, month or week.**
  - Reduce with `cdo ydaymean` (366 day-of-year means per outlet) and keep that daily climatology, so months, weeks or any other period come from one fetch. Today the daily file is deleted, so any new period means fetching all of PCIC again.
  - A week is a fixed day-of-year bin (week 1 = days 1–7, …, week 52 = days 358–365, with Dec 31 of leap years folded into week 52), not an ISO week number. An ISO week sits up to 3 days apart from year to year, and week 53 exists in only some years. A fixed bin covers the same calendar days in every year.
  - The output gains a `week` key in place of `month`: 52 rows per segment, about 175M rows against 40.5M, and a `.csv.gz` of roughly 950 MB against 220 MB.
  - Measure the routing lag on the first weekly build. Local runoff is an outlet's flow minus the flow of the outlets above it, and over a week, water still in transit makes it negative more often than over a month, especially on the rising freshet. Those values are clamped to zero. Count the clamped rows per week, monthly against weekly, before trusting weekly flow on mid-network segments.
- CMIP6 builds when a report needs projections (wet#57: "add projection rows when a report needs them"). A change is taken within each run, future over the run's own 1981–2010.

Relates to #6, #23, NewGraphEnvironment/wet#57, NewGraphEnvironment/wet#4, NewGraphEnvironment/wet#70 (wet#70 publishes per-segment daily flow, and its routed half is the day-of-year climatology kept here, so keep it as an output, not only as the step weeks are taken from).

## Exploration (plan mode, 2026-10-17)

- Everything after step 2 carries `month` through `fwapg.pcic_outlet_monthly`, `pcic_subbasins_monthly` (in `sql/pcic_crosswalk06_subbasins.sql`, lines 189–267) and the INSERT in `sql/pcic_crosswalk07_segments.sql`. The per-segment flow is linear in the period means of sub-basin flow until the final clamp. That is why the weights table is exact.
- The `no_series` flag is decided by whether an outlet has a series (`04_select.sql` lines 83 and 113). PNWNAmet over any years gives the same set of outlets, so the crosswalk is identical between those runs. For CMIP6 that is unmeasured.
- A full PNWNAmet fetch took about 32 min (cache mtimes 17:38–18:10, 2026-10-07), so refetching it to keep the daily climatology is cheap. The cached `data/monthly/*.csv` (ymonmean, 1951–2012) is the regression reference.
- The published fingerprint of today's monthly table (#9) is 40,524,444 rows over 3,377,037 segments, with `sum(round(q_m3s::numeric, 6))` = 178035348.248310. The rebuilt 1951–2012 run must reproduce it.
- QA (`sql/qa.sql`) is calibrated on monthly values, and the junction tests use June. So the monthly table is always built and gated by QA, and the weekly table is added on top when asked for.
- `whse_basemapping.pcic_fwa_crosswalk` is named in about 12 job files (04–07, qa*, review_*). The build moves to a staging name in `fwapg`, and only the export swaps into `pcic`.


## Errors Encountered

| Error | Resolution |
|-------|------------|
