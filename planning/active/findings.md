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


## Phase 1 probes (2026-10-17)

### cdo `ydaymean` bins by calendar month-day (CDO 2.6.0)

A synthetic daily file, 1951-01-01 to 2012-12-31 (22,646 steps, standard calendar), with each day's value
`cmonth()*100 + cday()`. `cdo ydaymean` gives 366 steps, and every step's mean equals its own date's
month*100 + day (0 mismatches). Feb 29 is a bin of its own (value 229), and Mar 1 stays 301. So the bins
are month-day, not day-of-year, and no `del29feb` workaround is needed. The output's dates carry the
last year (2012-..).

A bin's count is not in the output. For a period y1..y2 it is `y2 - y1 + 1` for every bin but Feb 29,
which holds the leap years in the period. On a non-trivial series (`sin(timestep*0.37)*50 + year*0.1`),
over 1981/2010, the monthly means of the day bins weighted by those counts match `cdo ymonmean` to
3.96e-8 relative, at all 12 months. That was compared with `ncdump -p 9,17`: `outputtab` prints 4
decimals, and a first pass with it showed a spurious 4.8e-5.

### hydromosaic CMIP6 bulk requests

- The exact strings `GET /outlets/4008184/timeseries` lists are model `CNRM-ESM2-1` and scenario
  `historical, ssp245` (with comma and space); likewise `historical, ssp585`. `BulkDownloadRequest` takes
  `model` and `scenario` as free strings (1-128 chars).
- Fifty outlets (the first 50 of `batch_004_0002`):
  - PNWNAmet: 200, 11 s, 7.6 MB, 23,011 steps from 1950-01-01 to 2012-12-31;
  - CNRM-ESM2-1 `historical, ssp245`: 200, 34 s, 18.1 MB, 55,152 steps from 1950-01-01 to 2100-12-31.

  Both use the `gregorian` calendar and `double streamflow(time, outlet)`. The two files hold the same
  50 `basin_name`s, every one requested.
- Three outlets from PNWNAmet's `missing.txt` (11000130, 11000131, 11000175) also return 422 for CMIP6.
  So the missing set looks shared, but that is measured on 3 of 28, not established.
- At about 3x PNWNAmet's time per outlet, a full CMIP6 run's fetch is roughly 1.5 h (PNWNAmet's took
  32 min). Not built here.

### Spec the code is tested against

- **Daily climatology key** `(month, day)`, 366 bins, with `n_days` = the number of days in the period
  falling in the bin.
- **Period mean** of any sub-basin quantity over a set of bins: `sum(q * n_days) / sum(n_days)`. For
  months this equals `ymonmean` (above).
- **Week** from `(month, day)`: `doy` = day of year of `(month, day)` in a 365-day year, with Feb 29 taking
  Feb 28's (59). Then `week = least((doy - 1) / 7 + 1, 52)`. Week 1 is Jan 1-7, week 9 is Feb 26-Mar 4
  (with Feb 29), and week 52 is Dec 24-31 (8 days, doy 358-365).
- **Segment flow for a period p:**
  `q(seg, p) = greatest(sum over u in upstream_subids of q_acc(u, p) + q_local(subid, p) * share, 0)`,
  where `q_acc` and `q_local` are the period means of the sub-basin daily table. The per-period sum is
  linear in the daily values, so this equals the old formula applied to the period-mean outlet flows. The
  clamp is applied per period, as before, never per day and then averaged.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `diff -q` failed: `unknown switch q` | `diff` is a shell function wrapping `git diff --no-index`; compare with `cmp` |
