# #25: PCIC crosswalk, routed flow for a chosen model, scenario, years and time step (with #23)

## Outcome

`extras/pcic_crosswalk/pcic_crosswalk.sh` now builds a run: `MODEL`, `SCENARIO` and `YEARS`, with `WEEKLY=1` adding weekly flow. The run's output goes into a new `pcic` schema (#23), keyed by `(model, scenario, period)`. The fetch no longer reduces each outlet to monthly means. It keeps a daily climatology, `cdo ydaymean`'s 366 calendar month-day bins, each weighted by how many days of the period it holds. Accumulation runs per sub-basin per day, and each FWA segment gets one set of weights (sub-basin, share, upstream outlets) that every run shares. Monthly, weekly or any window's flow is then exact from `pcic.subbasin_daily` and `pcic.segment_weights`.

The build stages in `fwapg.pcic_*` and swaps a run into `pcic` in one transaction. It refuses a crosswalk or weights that differ from the runs already there, and records fingerprints in `pcic.runs`. `load/pcic.sql` and `load/pcic_run.sql` load the published files against those fingerprints.

Two PNWNAmet runs are published to `fresh-bc/fwapg/extras/`: 1951-2012 (monthly) and 1981-2010 (monthly and weekly). The frozen `whse_basemapping` tables stay until wet reads `pcic` (wet#101); dropping them is #31. CMIP6 is supported and probed, not built.

What was learned is in `research/pcic_routed_flow_periods.md`:
- `ydaymean` bins by month and day, not day of year;
- the weights make any window exact;
- the crosswalk does not depend on the years;
- a weekly step adds no clamping.

Review: a Plan-agent review of the plan (18 findings, `review-plan.md`), then `/code-check` over the branch in 3 rounds (6, 5 and 3 findings, all fixed). The loop ended by enumeration (`review-enumeration.md`), because rounds 2 and 3 each found a defect inside the previous round's fix.

## Measurement

- **The rebuild is exact.** The 1951-2012 run rebuilt through the daily path equals the first build (#9) row for row:
  - 40,524,444 rows on 3,377,037 segments;
  - `sum(round(q_m3s::numeric, 6))` = 178035348.248310;
  - 0 rows differing.

  Monthly means derived from the daily cache match `cdo ymonmean` at all 584,256 (subid, month) pairs, to 2.5e-11 m³/s (1.0e-14 relative).
- **The crosswalk does not depend on the years.** Its md5 `b1a710836df2cafea0ef514b7ed1c338` is the same for 1951-2012, 1981-2010 and the first build. 28 of 48,716 outlets have no series.
- **Clamped rows at 1981-2010:**

  | step | all segments | mid-network |
  |---|---|---|
  | monthly | 0.978% | 0.049% |
  | weekly | 0.977% | 0.048% |

  The worst week is May 28-Jun 3, with 805 mid-network rows, against 774 in May. This settled the issue's worry that weekly flow would turn transit lag into mid-network clamping: it does not. Weekly flow is published, and the README carries the caveat.
- **Sizes (`.csv.gz`):**
  - weekly: 175,605,924 rows, 987.8 MB (the issue estimated 175M and about 950 MB);
  - monthly: 232 MB a run;
  - sub-basin daily: 280 MB a run (13,786,122 rows);
  - weights: 37.8 MB.
- **Runtime** (local Docker PostgreSQL 17.5, 128 GB machine): a monthly run takes 1 h 15 min, and `WEEKLY=1` 2 h 53 min. Of the weekly run's extra time, the swap of the weekly rows into a primary-keyed table took 79 min. The README's old figure, 28-33 min with downloads cached, is replaced.
- **Gauges** (`qa_gauges.sh`):
  - 1951-2012 repeats the first build: 494 of 538 within 10% of PCIC;
  - 1981-2010: 401 of 431;
  - PCIC over observed, median: 0.949 for 1951-2012, 0.988 for 1981-2010.
- **Loading from fresh-bc** into a new database: 33 min. Every fingerprint in `pcic.runs` was reproduced for both runs.
- **Wrong turns kept:**
  - `outputtab`'s 4 decimals first showed a spurious 4.8e-5 difference between the day bins and `ymonmean` (findings, Phase 1).
  - The weights file came out 26 bytes smaller in the second build. `upstream_subids` is unordered (940 of 87,444 arrays unsorted), which is the likely cause; it is not established, because the first file was overwritten. Compare the arrays as sets.

## Evidence

- `logs/run25_*.log`: the two build logs, the database URL replaced by `$DATABASE_URL`.
- `logs/qa_gauges_*.log`: the gauge checks.
- `tests/`:
  - `regress_daily_vs_ymonmean.sh`;
  - `compare_monthly_vs_first_build.sql`;
  - `test_pcic_export_load.sh`, the synthetic proof that every export guard and load refusal fires.

Closed by: PR PRLINK
