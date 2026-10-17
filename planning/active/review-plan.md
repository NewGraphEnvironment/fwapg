# Plan review — #25 (Plan agent, 2026-10-17, spawned 17:35Z)

Written here by the parent session: a Plan agent has no Write tool. The verdict on each finding is
recorded below; for the full text of the review, see the session transcript.

| # | Category | Finding | Verdict |
|---|----------|---------|---------|
| 1 | Blocker | `qa_gauges.sh` caches WSC pages by offset only, so a 1981-2010 run silently reuses 1951-2012 observations; it also loads `data/monthly/*.csv` for PCIC's own flow | Accepted: WSC cache per period, plus a year filter in `obs`; PCIC flow from the run's daily cache |
| 2 | Blocker (conditional) | the `del29feb` fallback does not renumber days | Moot: the Phase 1 probe showed cdo 2.6.0 bins by month-day; the awk reads (month, day) from `cdo showdate` and checks `k == nd*n` |
| 3 | Blocker | a wrong MODEL/SCENARIO turns into every outlet "missing" with exit 0 | Accepted: vars exported and passed with `--arg`; add a one-outlet preflight that must return 200, and a gate on the missing count |
| 4 | Gap | `n_days` must count the days present, or the weighting is not exact | Accepted: assert that a batch's daily series has no missing values within YEARS, so `n_days` is the calendar count; `n_days` lives in `pcic_day_bins` and is exported with `subbasin_daily` |
| 5 | Gap | QA "annual" metrics are plain means of 12 monthly means | Accepted: `pcic_outlet_monthly` and `pcic_subbasins_monthly` are materialised under the same names and shapes (08 with `table=monthly`) |
| 6 | Gap | the review tables follow the last run's flow | Accepted: build the reference run (PNWNAmet 1951-2012) last; record the run in `pcic_qa_build` |
| 7 | Gap | the md5 guard does nothing on a loaded DB; no recovery path; weights unfingerprinted | Accepted: export and load `pcic.runs`; weights fingerprinted (rows, share sum); recovery documented |
| 8 | Gap | how the run columns get into the rows | Decided (mechanism): every row of the per-run CSV carries model, scenario and period |
| 9 | Assumption | weekly 09 step and the swap are big single statements | 09 runs per watershed group (`xargs -P 4`); the swap is timed in Phase 5 |
| 10 | Assumption | 06's accumulation over 366 bins with no stats | Done: `ANALYZE` before the loop; a set-based update per level instead of a correlated one |
| 11 | Acceptance | 1e-6 relative is undefined at 0 and loose | Accepted: `abs(a-b) <= 1e-9 + 1e-12*abs(b)`, identical key sets, identical missing list |
| 12 | Acceptance | fingerprint equality will likely miss by k x 1e-5 | Accepted: a row-level diff against `whse_basemapping.fwa_stream_networks_discharge_monthly` |
| 13 | Acceptance | no weekly consistency test, no load test | Accepted: week-bin and n_days sums, weeks vs months annual mean; a scratch-DB load from S3 reproducing `pcic.runs` |
| 14 | Ordering | Phase 2 breaks the job until Phase 3; refetch is wasteful | Accepted: monthly compatibility tables; the 1951-2012 daily cache is reused; `data/monthly` kept until Phase 5 passes |
| 15 | Gap | rename list incomplete | Done via a grep over every job file; the shell lines are rewritten in Phase 4 |
| 16 | Gap | concurrent runs collide | README says runs are sequential |
| 17 | Assumption | CMIP6 calendars may differ by GCM | Accepted: probe `time:calendar` and the step count for all 9 GCMs |
| 18 | Scope | publish the week bins as a lookup; rename in its own commit | `pcic.day_bins (month, day, week)` published; the rename lands with Phase 4 |
