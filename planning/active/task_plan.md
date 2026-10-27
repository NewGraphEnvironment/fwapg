# Task: PCIC crosswalk: keep the per-year series from the hydromosaic fetch, so segment flow can be read year by year, 1951–2012 (#42)

**If we do it:** flow on an FWA segment can be read for one year, not only as a climatology, over 1951–2012, so a downstream estimate of change over time can weight its donor gauges by what PCIC models at the place and can be scored against PCIC's own years. **If we never do:** every PCIC table here is a mean over years (`pcic.discharge_monthly`, the weekly table, `pcic.subbasin_daily`), and a question about one year at an ungauged segment cannot be put to PCIC at all.

The fwapg half of NewGraphEnvironment/wet#122.

**Parked 2026-10-26.** The plan gate approved the baseline only; the run-to-PR mandate starts at the resume instruction (`progress.md`, Resume). The Plan review (`review-plan.md`, 18 findings) is folded in below.

## Context

`extras/pcic_crosswalk/pcic_crosswalk.sh` fetches each batch's daily streamflow from hydromosaic as NetCDF (`double streamflow(time, outlet)`, 23,011 gregorian days from 1950-01-01, `_FillValue -9999`; measured 2026-10-26 on outlet 4008184, 180 KB per outlet), reduces it with `cdo ydaymean -selyear,$YEARS` to a 366-bin climatology and **deletes the NetCDF**. Every published PCIC table is therefore a mean over years, and a question about one year at an ungauged segment (wet#122, wet#118) cannot be put to PCIC at all. The crosswalk and `pcic.segment_weights` already route any set of days to segments exactly (`research/pcic_routed_flow_periods.md`: routing is linear until the clamp), so what is missing is the days themselves, per year, per sub-basin.

What exists and is reused:
- `sql/pcic_crosswalk06_subbasins.sql`, its daily section (from "flow generated inside each placed outlet's sub-basin" to the end): outlet runoff → sub-basin `q_local` → `q_acc` accumulated down the FWA parent tree (a `DO $$` loop over `fwa_depth`). This is the arithmetic the per-year rows need, run once per year on 37,667 × 365 rows — the same size as the climatology it runs on today. The section also carries one-time work (`ADD COLUMN fwa_depth`, its recursive UPDATE, the cycle check, `ANALYZE pcic_subbasins`) that must stay in 06.
- The job's existing NetCDF → `subid,month,day,q` path (`cdo`/`ncdump`/awk in `fetch_batch`), which already refuses a missing day and a fill value.
- `sql/pcic_export.sql`, `load/pcic_schema.sql`, `load/pcic.sql`, `load/pcic_run.sql`: the fingerprint-and-refuse pattern (`pcic.runs`) the new catalogue follows.
- `pcic_test.sh`: the fixture-based harness (107 checks, ~25 s) the new tests extend.
- What the job needs: a PostgreSQL 15+ build database with the FWA loaded and about 30 GB free for staging, about 16 GB of disk for the kept NetCDF and the parquet files, `uv` (pyarrow + netCDF4 resolve in about 20 s), and `fresh-bc` for the publish (it answers HTTP range requests with 206, and moves objects to Standard-IA after 30 days).

## Decided at the gate (2026-10-26, the owner; recommended option first, taken as recommended)

1. **Product shape.** (a) **Per-sub-basin days as parquet, one file per year** — any window, any year, routed on demand through `pcic.segment_weights` as `pcic.subbasin_daily` is; nothing large enters Postgres; no second fetch ever. (b) Per-year months and weeks in Postgres (28 M / 121 M rows): SQL-native but a window off month or week edges cannot be read. (c) Per-year window statistics for a passed-in window set: smallest, and ties fwapg to wet's windows. **Decided: (a)**; (b)'s per-year months are computed as a QA staging table, not published.
2. **File and column layout.** `pcic.subbasin_days.<model>_<scenario>.<year>.parquet`, flat beside the other files (one GET per year, matches the existing naming), columns `subid int32, date date32, q_local float32, q_acc float32`, sorted by `subid, date`, zstd, row groups of 1,000 sub-basins (≈365 k rows, ≈38 groups per file, so min/max statistics prune by `subid`); every year the series holds (1950–2012 for PNWNAmet, 63 files; 1950 named in the README as the model's start-up year, as `YEARS` already drops it). Alternatives: hive `year=` directories (duckdb-idiomatic, more keys to list); `year`+`doy` ints (the issue's probe measured 5.1 GB against 6.8 GB for `date`, but on one 63-year file, where `date` has 23,011 distinct values per sub-basin; in a per-year file it has 365 and should encode like `doy`); float64 (+40%). **Decided: the flat per-year file with a `date` column**, confirmed by writing the Phase 2 timed year both ways and recording both sizes; `year`+`doy` is taken only if `date` costs more than 1.5 GB over the series.
3. **Catalogue.** New table `pcic.series` keyed `(model, scenario, year)`: `crosswalk_md5`, `rows`, `subbasins`, `q_local_sum`, `q_acc_sum`, `bytes` (the file's size, so a truncated download is caught before parsing), `built_at`; published as `pcic.series.csv.gz`, loaded by `load/pcic.sql`, which refuses a catalogue built on another crosswalk than the published one. The sums are defined so every reader reproduces them bit for bit: `sum(floor(double(v) * 1000 + 0.5))` as a 64-bit integer over the stored float32 values `v` (Postgres `q::real::double precision`, pyarrow `cast(float32)` then float64, duckdb `CAST(q AS DOUBLE)`, R `as.double`); `double(v) * 1000` is exact for a float32 (24 + 10 bits < 53), so `floor` is identical everywhere and ties never arise; NULL and NaN are refused. The parquet files are never loaded into Postgres. Alternative: widen `pcic.runs` — wrong key (`period`); the days belong to a model and scenario, not to a period. **Decided: `pcic.series`.**
4. **What is published.** Sub-basin days only (37,667 sub-basins × 23,011 days, ~5–8 GB). The raw per-outlet NetCDF (48,688 outlets, ~9 GB at 180 KB each) is kept locally in `data/nc/<model>_<scenario>/`, which is the issue's "one fetch": a new `YEARS` or `DAYS=1` run derives from it without hydromosaic. Alternative: also publish per-outlet days (+6.6 GB, PCIC's own series with no crosswalk) — not now; wet#122 reads routed flow at segments. **Decided: sub-basin days only.**

**Pending at resume (the user's call, a column in stored data); taken as recommended on 2026-10-27 while the user was away, named in the PR (`findings.md`):** whether `pcic.series` carries a `commit` column naming the fwapg commit that built the files. wet's reader (wet#122, `scripts/departure_pcic.R`) consumes decision 2's layout and decision 3's fingerprints as is, and takes the files' commit from an env var (`WET_FWAPG_DAYS_COMMIT`) because `pcic.series`, like `pcic.runs`, names none. Recommended: add `commit text` to `pcic.series` (the job writes `git rev-parse HEAD` at export; one column, and the reader can drop its env var). Alternative: leave it out, as `pcic.runs` does, and keep the env var.

Mechanism, chosen and stated (not asked):
- The days are opted into with `DAYS=1` (like `WEEKLY=1`), independent of `YEARS`: the kept file spans the model's whole run, so the fetch's `NDAYS` check on `-selyear,$YEARS` still holds for any period, and the climatology stays per run in `data/daily/<run>/`.
- Batch lists and the kept NetCDF move to per-`<model>_<scenario>` directories (`data/series/`, `data/nc/`); the existing `data/daily/<run>/` caches stay valid, the old `data/series/<run>/` directories are abandoned.
- NetCDF → per-year rows is Python (`pcic_days.py rows`, PEP 723 inline deps, `uv run --script`; `python.md`), not the shell path: the shell path would run `cdo -selyear` plus `ncdump`/awk once per batch per year (244 × 63 ≈ 15,000 invocations), and reading a year slice from each kept file in one process is the cheaper shape. The climatology keeps the shell path unchanged. Two conversions of one format exist, so Phase 3 tests that they agree on a synthetic file, and the rows go through two text passes per year (COPY in, COPY out), which the Phase 2 timing records. The same script writes the parquet (`parquet`) and recomputes a file's catalogue line (`fingerprint`).
- The per-year arithmetic is the daily section of 06 split into `sql/pcic_crosswalk06_daily.sql` parametrised by `:src` and `:dst`, run by the climatology and by every year. psql substitutes nothing inside a dollar-quoted body, so the depth loop takes its table from `set_config('pcic.dst', :'dst', false)` and builds each UPDATE with `EXECUTE format(..., current_setting('pcic.dst'))`.
- The loop sits after the run's `.csv.gz` exports and before `pcic_outlets` is renamed to `pcic_qa_outlets` and the staging is dropped: that is the one slot where `pcic_outlets`, `pcic_fwa_crosswalk`, `pcic_subbasins`, `pcic_subbasins_daily`, `pcic_day_bins`, `pcic_segment_weights` and the run's row in `pcic.runs` all exist.
- The per-year clamp is counted exactly on mid-network segments for every year, from a per-year monthly sub-basin staging table the loop accumulates (37,667 × 12 × 63 = 28 M rows, dropped at the end), through `09_discharge.sql` restricted to mid-network segments; the sub-basin proxy (negative `q_local`) is neither necessary nor sufficient (a segment clamps iff `U + share × L < 0`).

## Phase 1: Fetch keeps the NetCDF
- [x] `pcic_crosswalk.sh`: batch lists in `data/series/<model>_<scenario>/`, NetCDF kept in `data/nc/<model>_<scenario>/<batch>.nc`, downloaded to `<batch>.nc.tmp` and moved into place only after the `ncdump -h` check, so a killed download is never a kept file. `fetch_batch` checks in this order: a kept `.nc` whose `basin_name` set equals the batch list → reduce only if the run's `.csv` is missing; no `.nc` and (`DAYS=1` or the `.csv` missing) → fetch; `.csv` present and `DAYS=0` → return. The split-on-422 and `missing.txt` logic unchanged but per model and scenario
- [x] `DAYS` env (`0`/`1`, validated like `WEEKLY`); with `DAYS=1` every batch ends with its `.nc`, checked after the fetch. `FETCH_ONLY=1` stops the job after step 2 (for this phase's run and for a cache warm-up)
- [x] README's cache paragraph follows the moved directories (`qa_gauges.sh` reads `data/daily/<run>/` only, which does not move)
- [ ] Run `DAYS=1 FETCH_ONLY=1 ./pcic_crosswalk.sh` for PNWNAmet historical: every batch's `.nc` kept, `missing.txt` has 28, elapsed (from `date -u`) and bytes on disk (`du`) in `findings.md`

## Phase 2: Per-year sub-basin days
- [x] Split 06: 06 keeps the crosswalk UPDATE, `fwa_parent_subid`, `pcic_subbasins`, `ADD COLUMN fwa_depth`, its recursive UPDATE, the cycle check and `ANALYZE pcic_subbasins`, then calls `sql/pcic_crosswalk06_daily.sql` with `src=pcic_outlet_daily dst=pcic_subbasins_daily`. `06_daily` = `DROP`/`CREATE :dst AS` runoff → `q_local` (reading `:src`, `pcic_outlets`, `pcic_fwa_crosswalk`, `pcic_subbasins` by name), the depth loop through `set_config`/`EXECUTE format`, `ANALYZE :dst`. The climatology's output is unchanged: proven by the fixture test in Phase 3 and by Phase 5's fingerprints
- [x] `pcic_days.py` (PEP 723, `uv run --script`): `rows <year> <nc...>` prints `subid,month,day,q_m3s` for one year from the kept NetCDF, refusing a fill value, a missing day or a duplicate outlet; `parquet <out>` reads `subid,month,day,q_local,q_acc` for one year from stdin and writes the file of decision 2; `fingerprint <file...>` prints each file's catalogue line (`year, rows, subbasins, q_local_sum, q_acc_sum, bytes`) by decision 3's definition
- [x] Per-year loop in `pcic_crosswalk.sh` (`DAYS=1`, in the slot named under Mechanism): per year of the series (`cdo showyear` on one kept file), `\copy` into `fwapg.pcic_outlet_year`, `06_daily` with `src=pcic_outlet_year dst=pcic_subbasins_year`, `INSERT` the year's monthly means into `fwapg.pcic_subbasins_months (year, subid, month, q_local, q_acc)`, `\copy ... TO STDOUT` into `pcic_days.py parquet data/days/<model>_<scenario>/<year>.parquet`; a kept file skips its year's COPY and SQL, so the loop resumes, and the months table is rebuilt for a skipped year from its file (`pcic_days.py` reads it back) so the QA sees every year; `pcic_outlet_year`, `pcic_subbasins_year`, `pcic_subbasins_months` join the final `DROP`
- [ ] Time one year on the real data in a scratch copy of the staging (`pcic_fwa_crosswalk` from `pcic.fwa_crosswalk`, `pcic_outlets` from `fwapg.pcic_qa_outlets`, `pcic_subbasins` with `fwa_depth` rebuilt from `fwa_parent_subid` by 06's recursive CTE and `local_area_ha` from the area query): the rows pass, COPY, `06_daily`, the months INSERT, the parquet write, and the file written both ways (`date` and `year`+`doy`) with both sizes, all in `findings.md`; the series total projected. If a year takes over 5 min, switch the accumulation to a closure-table join and re-measure before the loop is committed (then "reproduces #25's fingerprints" holds at the 6-decimal `pcic.runs` sums, since summation order changes)

## Phase 3: Catalogue, export and loads
- [x] `load/pcic_schema.sql`: `pcic.series` (decision 3)
- [x] `sql/pcic_export_days.sql`: replace the model and scenario's rows of `pcic.series` from `pcic_days.py fingerprint` over every file in `data/days/<model>_<scenario>/` (so a resumed loop is complete), in one transaction; refuse a crosswalk md5 unlike the runs in `pcic.runs`, a year of the series with no file, or a file whose year is not in the series
- [x] `pcic_crosswalk.sh` exports `pcic.series.csv.gz` on every run (`DAYS=0` too, from `pcic.series` as the build database holds it, possibly empty), since `extras/README.md`'s upload loop takes every `pcic.*.csv.gz` and `load/pcic.sql` fetches it with the shared tables; `extras/README.md` gains the upload line for the parquet files
- [x] `load/pcic.sql` fetches `pcic.series.csv.gz` with the shared tables, accepts an empty catalogue, refuses one built on another crosswalk, and keeps a local unpublished series as it keeps a local run; `pcic_test.sh`'s `local_load` sed and its count go from 4 to 5; `load.sh` unchanged otherwise (parquet never loaded)
- [x] `pcic_test.sh` (needs `uv`; fails with a clear message without it): a separate `06_daily` fixture (its own `pcic_outlets` with PCIC children, a `pcic_fwa_crosswalk` with an unplaced outlet anchored to a placed one and an FWA parent chain, `pcic_subbasins` with `fwa_depth`) written to its own table and compared with hand-computed `q_local`/`q_acc`, leaving the existing 107 checks untouched; three fixture years whose calendar-day mean equals the fixture climatology; `pcic_days.py rows` equal to the `cdo`/`ncdump`/awk path on a synthetic NetCDF, and refusing a fill value and a missing day; the loop's parquet read back equal to the staging rows at float32 and its `fingerprint` line reproduced in SQL by decision 3's formula; `pcic_export_days.sql`'s refusals; `load/pcic.sql` loading and refusing the catalogue

## Phase 4: QA for the years
- [x] `sql/qa_days.sql` (runs after the loop; a failure keeps the staging and exits 1 as `qa.sql` does): the per-bin mean over `YEARS` of the published files, read back by `pcic_days.py` (which also returns each bin's mean of `|v|`) and `\copy`'d in, equals `fwapg.pcic_subbasins_daily` bin for bin within `abs(diff) <= 2^-23 * mean_abs + 1e-9` m³/s — float32 rounding is relative to each value, so a bin whose `q_local` changes sign across years (a losing reach) can have a mean near 0 while its values are not, and a tolerance keyed to `abs(clim)` floors too low there (wet#122's parity check uses this bound; raised by the wet session 2026-10-26) — the max observed recorded; and, when every year ran in this invocation, the float64 `pcic_subbasins_months` means over `YEARS` equal `pcic_subbasins_monthly` to 1e-9 relative. The header states the transitive closure of the issue's first check: `discharge_monthly` = 09(08(`subbasins_daily`)); the mean over years and 08's `n_days`-weighted mean are linear and commute; the clamp and the 5-decimal round are applied once after averaging in both paths, so a reader averaging the published files reproduces `discharge_monthly` to about 1e-7 relative, not at 5 decimals row for row
- [x] `sql/qa_report_days.sql`: per year and month, mid-network segment-months clamped (09's formula restricted to mid-network segments, from `pcic_subbasins_months` with a per-year `n_days`), beside the climatology's count from `qa_report_clamped.sql`; the worst and best years named
- [ ] Direct closure for one watershed group: the read-back mean routed through the README's window query equals `pcic.discharge_monthly` for that group within the stated tolerance
- [x] `pcic_test.sh`: `qa_days.sql` passes on the fixture and fails when one year's file is perturbed

## Phase 5: Build and publish PNWNAmet 1951–2012 with the years
- [ ] `DAYS=1 ./pcic_crosswalk.sh` (defaults) in the background with `date -u` at start and end, nothing it reads edited while it runs; the trace log kept under `planning/active/logs/` with `DATABASE_URL` scrubbed to the literal `$DATABASE_URL` before any commit (the trace prints `PSQL`'s URL on every line)
- [ ] The rebuilt run reproduces #25's fingerprints: `monthly_q_sum` 178035348.248310 over 40,524,444 rows and 3,377,037 segments, `daily_q_sum` 633459324.098216, so the 06 split changed nothing; 0 POSTs to `/hydromosaic/bulk-downloads` in the trace (grep), which is the issue's third check
- [ ] `qa_days.sql` passes (max deviation recorded); `qa_report_days.sql`'s table and the per-year timing in `findings.md`
- [ ] Publish the 63 parquet files and `pcic.series.csv.gz` to `s3://fresh-bc/fwapg/extras/` (bytes and elapsed recorded; the user runs the bare `aws s3 cp` loop if auto mode refuses the write); `load/pcic.sql` into a scratch database loads the catalogue from fresh-bc
- [ ] Read one published year over HTTP with R's duckdb (`httpfs`): rows, `bytes` and both sums reproduced from the catalogue, versions and elapsed recorded; the README's year-by-year window query for one watershed group runs against the published files

## Phase 6: Documentation
- [ ] `extras/pcic_crosswalk/README.md`: `DAYS`, `FETCH_ONLY`, the kept NetCDF and what a rerun now needs, the per-year product and its catalogue with the fingerprint formula, the duckdb (and R) query for flow on a segment for one year or every year of a window, sizes, timings, the per-year clamp caveat, 1950 as the start-up year, `uv` in requirements and in the test paragraph
- [ ] `research/pcic_routed_flow_years.md` (header per `planning.md`) and its row in `research/README.md`; `pcic_routed_flow_periods.md` cross-references it
- [ ] Issue #42 body: `## Plan` kept current, sizes measured, decisions recorded, the first check's "row for row" restated as the tolerance tested; a comment on wet#122 naming the published files and the query
- [ ] `/code-check branch`, `/planning-archive` (README with the Measurement list below and Evidence), `/gh-pr-push --base newgraph`

## Measurement the archive README must carry

- The 63 files: bytes each and in total; the `date` against `year`+`doy` sizes of the timed year.
- The fetch: elapsed and bytes on disk; 0 hydromosaic POSTs in the Phase 5 trace.
- Per-year loop time (rows pass, COPY, `06_daily`, months, parquet) and the whole `DAYS=1` job's time.
- `qa_days.sql`: tolerance and max deviation observed; the one-group direct closure's max deviation.
- The per-year clamp table: worst and best years with their mid-network segment-month counts beside the climatology's.
- Both #25 fingerprints reproduced.
- The publish (bytes, elapsed) and the HTTP read-back (year, rows, sums, duckdb and R versions, elapsed).
- That 63 files (1950–2012) are published while the title's 1951–2012 is the climatology's default `YEARS`.

## Owed at the end (reported, done after merge)

None. CMIP6 per-year builds are not in scope (the job takes them; nothing is built).

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved:
- `PGSERVER=... ./pcic_test.sh` green after each phase (Phases 2–4 add checks); a mutation pass on the new guards as #25 did (`tests/mutations/`): each refusal shown to fire.
- Phase 5's build log: QA all `t`, `qa_days.sql` `t`, `pcic.runs` fingerprints equal to #25's, the catalogue's 63 rows.
- A published year read back over HTTP by duckdb equals its catalogue row; a scratch database loads the catalogue through `load/pcic.sql`.
- Timings and sizes recorded from `date -u` and `ls -l`, not from how long it felt.

## Risks named

- The per-year loop's wall time is unmeasured until Phase 2; the contingency (closure-table accumulation) is in the plan, and the loop resumes per year. The build is 1 h 15 min (the #25 monthly run) plus 63 × the measured per-year time, so up to about 6.5 h at the 5-min threshold, in the background; docs and the issue body are the work done beside it.
- The S3 upload is a production write auto mode may refuse once; the bare command is handed over then.
- The fetch is about 9 GB of NetCDF through PCIC's server once (27 min in #25 for the same batches); the NetCDF is kept so it never repeats.
