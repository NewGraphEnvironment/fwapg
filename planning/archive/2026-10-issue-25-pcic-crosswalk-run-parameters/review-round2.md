# Code-check round 2: branch `25-pcic-crosswalk-run-parameters` (8a0af41 vs newgraph)

Reviewer: read-only. No database touched and no repo file edited except this one. Shell and cdo
snippets were run on synthetic data in a temp dir (CDO 2.6.0, /bin/bash 3.2). Public reads: the
hydromosaic `/outlets/4008184/timeseries` listing, and HEAD requests to the fresh-bc bucket.

## Findings

- **[bug, docs] extras/pcic_crosswalk/README.md:269 and :280.** The date-window example filters on
  `make_date(2001, month, least(day, 28))`. That clamps day 29, 30 and 31 of **every** month to the
  28th, not just Feb 29. The note on line 280 ("`least(day, 28)` only matters for Feb 29") is therefore
  false. The example window (Jul 15 - Sep 7) happens to come out right, because both of its ends fall
  on a day of 28 or less. Any window with an end on the 28th or later does not:
  - a window ending Jun 28 also takes Jun 29 and 30 (both map to Jun 28);
  - a window starting Jul 30 loses Jul 30 and 31 (both map to Jul 28, before the start);
  - a window of Jan 29-31 is empty.

  This is the SQL a reader copies for "flow for any window". Fix: use the mapping that
  `sql/pcic_crosswalk01_days.sql:32` already uses, `make_date(2001, month, least(day, CASE WHEN month = 2
  THEN 28 ELSE 31 END))`, or write it as `CASE WHEN month = 2 AND day = 29 THEN 28 ELSE day END`. Then
  the note on line 280 is true.

- **[fragile, fails toward pass] extras/pcic_crosswalk/sql/pcic_export.sql:134 and load/pcic.sql:50:
  the guard's remedy leaves rows no guard can see.** Both RAISE messages say "rebuild them, or remove
  them from pcic.runs, first". An operator who does just that, `DELETE FROM pcic.runs WHERE ...`,
  leaves the run's rows in `pcic.subbasin_daily`, `pcic.discharge_monthly` and `pcic.discharge_weekly`.
  Both guards enumerate runs **only from `pcic.runs`**, and so do load/pcic.sql's new deletes (via
  `runs_in`). From then on:
  - the next export or load swaps in the new crosswalk and weights;
  - the removed run's rows stay in place, built on the old crosswalk and weights, with no fingerprint
    row;
  - nothing ever checks or removes them, and a `WHERE (model, scenario, period) = ...` query still
    returns them.

  The README (line 253) and the export header (lines 10-11) both say "and its tables", but the message
  the operator sees at the failure does not. Fix: name the tables in both messages. A guard that cannot
  be sidestepped this way would also refuse when a per-run table holds a `(model, scenario, period)`
  with no `pcic.runs` row. In the export, that is a `SELECT DISTINCT model, scenario, period` over the
  three tables `EXCEPT` the current run, compared against `pcic.runs`.

- **[fragile, low] extras/pcic_crosswalk/README.md:252-254: the README describes the guard as it was
  before round 1.** It says "a run whose crosswalk differs from one another run in `pcic.runs` was built
  on is refused". Since fix 4, the export (pcic_export.sql:131-132) and load/pcic.sql:48 also refuse a
  run whose **weights** fingerprint differs. A changed FWA (upstream areas, the watershed lookup,
  `blk_paths`) can trigger that with an identical crosswalk, and the README gives no reason for that
  refusal. Say "crosswalk or weights" there.

- **[fragile, low, docs] extras/pcic_crosswalk/README.md:41.** "With the downloads cached, the job took
  28-33 min (2026-10-10 ...), about ... 6 min writing flow per segment" is a measurement of the old
  monthly job, made a week before this branch. The new job does more work, and the README presents the
  number as this job's:
  - it accumulates per calendar day (06 updates about 13M rows per depth level in place of about 0.44M);
  - it builds weights and then one period table per step;
  - it inserts about 13.4M `subbasin_daily` rows and, with `WEEKLY=1`, about 175M weekly rows.

  Phase 5 already plans to measure the runtime. Replace the number with that measurement, or date it as
  the first build's.

- **[fragile, low] qa_gauges.sh / review_build.sh:37-40: the gauge table's run is never compared with
  the build's.**
  - `fwapg.pcic_qa_build` stores `model, scenario, period` (pcic_crosswalk.sh:306-309).
  - `fwapg.pcic_qa_gauges` records no run at all.
  - `review_build.sh` checks only that both tables exist and that the crosswalk md5 matches.

  So `qa_gauges.sh` run with its defaults (1951/2012) after a 1981-2010 build, which is the order Phase
  5 lists, passes review_build.sh. The review's `flagged` stratum then takes gauges from one run
  (review_build.sh:136-138) and `pcic_qa_flow` from another (review_sample.sql:80). The README's line
  128 ("Build the reference run last") is the only safeguard. Fix: have `qa_gauges.sh` refuse unless
  its `MODEL/SCENARIO/PERIOD` equal the stamp's, or have `review_build.sh` compare a run column written
  into `pcic_qa_gauges`.

## The round 1 fixes, checked

1. **missing.txt (pcic_crosswalk.sh:182-183).** Correct. Tested under `set -euo pipefail` on bash 3.2:
   - with no file, `n` stays 0 and the script continues. The failing `[ -e ]` is not the last
     command of the `&&` list, so `set -e` does not fire;
   - with a file, `n` is the line count;
   - `[ "      28" -le 100 ]` accepts BSD `wc`'s padding.
2. **YEARS past the series (pcic_crosswalk.sh:36, 117, 165).** Correct, and it fails closed. On a
   synthetic daily series from 1950-01-01 to 2012-12-31:
   - `cdo -s ntime -selyear,1951/2012` prints exactly `22646`, which equals the psql NDAYS, with nothing
     else on stdout;
   - `1991/2020` gives 8036, not 10958;
   - `2013/2020` gives empty output, so the batch returns 255.

   NDAYS assumes the Gregorian calendar, and all 18 CMIP6 streamflow series hydromosaic lists have
   `num_times` 55,152 from 1950-01-01 to 2100-12-31, which is Gregorian (no-leap would give 55,115). So
   the README's line 356 claim holds. One residual: a per-run cache written before this fix bypasses the
   check on resume (a batch with a CSV is skipped). Only `pnwnamet_historical_1981-2010` exists, and
   PNWNAmet covers it.
3. **qa_gauges.sh day bins (qa_gauges.sh:71-79, 89).** Correct. It no longer creates, reads or drops
   `fwapg.pcic_day_bins`, and neither `qa_gauges.sql` nor `qa_gauges_report.sql` reads it. The inline
   counts equal 01's `n_days` for every bin that exists.
4. **Weights in the export guard (pcic_export.sql:115-137, 173).** Correct. `pcic.runs` now records the
   fingerprint of `fwapg.pcic_segment_weights`, which is inserted unchanged, so the values are the ones
   the old code took from `pcic.segment_weights`. The numeric sum and bigint count compare exactly.
   - **Residual risk, not a defect of the fix:** `share` and `local_area_ha` are float8 sums whose
     input order follows the join plan, and ANALYZE samples randomly. Two runs on the same FWA could
     therefore differ in one `round(share, 9)` and be refused at export.
   - Before the fix the same equality was already required at load (load/pcic.sql:39), so the fix only
     moves the failure earlier, which is better.
   - Unmeasured; the 1981-2010 then 1951-2012 exports will show it.
5. **Stale rows of published runs (load/pcic.sql:54-78).** Correct for runs listed in `pcic.runs`.
   - **Order:** the deletes run before `pcic.runs` is replaced, and they compare the local claimed
     fingerprint, crosswalk included, with the incoming one per table.
   - **NULLs:** `IS NOT DISTINCT FROM` keeps a run with no weekly flow on both sides.
   - **Invariant:** a run's rows are either what `pcic.runs` describes or absent, never stale. A
     `pcic_run.sql` that fails after the swap leaves the run absent, and the next load.sh fills it.
   - **Gap:** rows of a run with no `pcic.runs` row are outside this fix. That is finding 2.
6. **Fixed-year day bins (01_days.sql:17-34).** Correct. Always 366 rows. Feb 29 gets `n_days` 0 in a
   period with no leap year, and its week is 9. The downstream reads are consistent:
   - the outlet check (pcic_crosswalk.sh:192) counts only bins with `n_days > 0`;
   - 08 and the export inner-join from the daily tables, which then have no Feb 29;
   - qa_weekly.sql's `leap_days` is 0 there;
   - load/pcic.sql's `!= 366` holds for every export.

## Also checked, no action

- **08, 09 and the README formula (lines 106-107)** match the spec in findings.md: `n_days` weighting,
  the clamp per period, rounding at 5 decimals in 09 only.
- **The README window example's segment query** matches 09. `window_flow` covers every subid, which is
  needed because `upstream_subids` can lie in other groups.
- **Docs quantities.** 175M weekly rows = 3,377,037 x 52. 40.5M monthly rows = 3,377,037 x 12. The
  CMIP6 list and the Gregorian claim match the live listing. The CLAUDE.md lines 19-21 commands are
  valid: psql accepts several `-f`.
- **Export files** (`*.gz`) and `data/` are gitignored.
- **No published `pcic.*` file is on S3 yet.** HEAD requests for `pcic.runs.csv.gz` and the shared and
  per-run files return 403, which is absent on this bucket; the frozen `pcic_fwa_crosswalk.csv.gz`
  returns 200. Until the Phase 6 upload, load.sh on `newgraph` fails at `load/pcic.sql`. It fails
  closed, but merge only after the upload.
- **The build running now is from commit 7bccc64, not 8a0af41.** It runs in the
  `/Users/airvine/Projects/repo/fwapg-build-25` worktree at 7bccc64, which has no NDAYS line in its
  trace, so none of the round 1 fixes are in it. For PNWNAmet 1981-2010 that changes no output:
  - the period has leap years;
  - missing.txt exists;
  - the series covers the years;
  - the old export took the same weights values.

  But that worktree's `qa_gauges.sh` is the pre-fix one, which drops `fwapg.pcic_day_bins`. Do not
  run it from there while the build runs. That worktree shares `data/` with this one through a
  symlink.
