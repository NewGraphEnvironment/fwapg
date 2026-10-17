# Code-check round 1: branch `25-pcic-crosswalk-run-parameters` (diff vs newgraph)

Reviewer: read-only. No database touched. Shell, cdo and ncdump snippets were run on synthetic data in a temp dir.

## Findings

- **[bug] extras/pcic_crosswalk/pcic_crosswalk.sh:177.** `n=$(cat "$SERIES/missing.txt" 2> /dev/null | wc -l)` aborts the script under `set -euxo pipefail` whenever `missing.txt` does not exist. That is the case for any run in which no outlet returns a 422 on its own. `cat` fails, `pipefail` makes the substitution's status 1, and `set -e` exits right after a fetch that succeeded. The error is sent to /dev/null, so only the `-x` trace shows where it stopped. Reproduced: a script containing only `set -euxo pipefail` and that line exits 1. The PNWNAmet run escapes only because 28 outlets are missing, which writes the file. A CMIP6 run, or any run whose missing set is empty, cannot finish. Fix: `n=0; [ -e "$SERIES/missing.txt" ] && n=$(wc -l < "$SERIES/missing.txt")`.

- **[fragile, fails toward pass] extras/pcic_crosswalk/pcic_crosswalk.sh:24, 113-116.** A `YEARS` that runs outside the years hydromosaic serves is accepted, and the run is labelled with a period its data does not cover. The missing-value check (`setmisstoc`/`timsum`) counts missing values only in time steps that exist, and `selyear` only warns about absent years. Measured on CDO 2.6.0 with a synthetic 1950-1953 file: `-selyear,1951/1960` printed `miss` = 0 (warnings only on stderr), and `ydaymean` still gave 366 bins, so the 366-bin check at line 186 also passes. `pcic_day_bins.n_days` then comes from the calendar of the requested years. The result is a run published as e.g. `pnwnamet_historical_1991-2020`, which is the current WMO normal and a plausible request, built from 1991-2012 data, with its Feb 29 weight wrong. `YEARS=1945/2012` likewise pulls in the 1950-01-01 start-up day the default deliberately drops. Fix: in `fetch_batch`, require `cdo -s ntime -selyear,"$YEARS" "$nc"` to equal the number of days in YEARS. Alternatively, check YEARS up front against the series' start and end in the `/outlets/4008184/timeseries` listing that line 165 already fetches.

- **[fragile] extras/pcic_crosswalk/qa_gauges.sh:66, 73, 84.** `qa_gauges.sh` runs `sql/pcic_crosswalk01_days.sql`, which drops and recreates `fwapg.pcic_day_bins`, the build's staging table, under the build's own name. At line 84 it then drops that table.
  - **Concurrent build:** running `qa_gauges.sh` while `pcic_crosswalk.sh` runs (one is running now) replaces the build's day bins with the QA script's YEARS. Depending on timing, the build either fails, or silently computes period means and exports `pcic.subbasin_daily.n_days` (pcic_export.sql:43-46) from the wrong period's counts.
  - **Failed build:** running it after a build failed QA destroys a staging table that was kept for debugging.

  Fix: give the QA copy its own name, for example by parameterising the table name in 01_days.sql, or build `pcic_qa_day_bins` inline.

- **[fragile] extras/pcic_crosswalk/sql/pcic_export.sql:22-34 (guard), 35-38 (swap).** The guard that protects the shared tables compares only the crosswalk md5, but `pcic.segment_weights` is shared too, and its contents do not depend on the crosswalk alone. The weights also come from `fwa_watersheds_upstream_area`, `fwa_streams_watersheds_lut` and `blk_paths`, none of which the crosswalk md5 covers. A later run exported after an FWA reload or a `blk_paths` rebuild therefore passes the guard and replaces the weights under every other run. Two things follow:
  - **The older runs no longer match their weights:** their discharge rows were built on the previous weights, and nothing records this.
  - **The published bundle stops loading:** the older runs' rows in `pcic.runs` keep the old `weights_rows`/`weights_share_sum`, so the exported `pcic.runs.csv.gz` fails `load/pcic.sql`'s weights check (line ~37) on every machine.

  Fix: in the same DO block, also refuse when another run's `(weights_rows, weights_share_sum)` differs from the fingerprint of `fwapg.pcic_segment_weights`.

- **[fragile, fails toward pass] load/pcic.sql:43-46 with load.sh:189-195.** The other-crosswalk guard skips every run that is listed in the published `pcic.runs`, on the assumption that the run's rows will be reloaded. load.sh, however, reloads only `subbasin_daily` and `discharge_monthly`, and only for the two hard-coded runs.
  - **Weekly rows:** in a database that built a run locally on another crosswalk (for example the build host after an FWA change), that run's `pcic.discharge_weekly` rows stay in place.
  - **Other runs:** the same goes for all rows of any other published run that load.sh does not iterate.

  Those rows now sit under the replaced `pcic.fwa_crosswalk`, `pcic.segment_weights` and a `pcic.runs` row carrying the published fingerprints, and nothing checks or removes them. Fix: in load/pcic.sql, delete the per-run rows of any run whose stored md5 differs from the incoming one. At minimum, delete its `discharge_weekly` rows and the rows of runs load.sh does not reload, or extend the guard to them.

- **[fragile, low likelihood] extras/pcic_crosswalk/sql/pcic_export.sql:39.** `pcic.day_bins` is shared, but every export replaces it with the current run's bins. YEARS is validated only as `y1 <= y2`, so a run whose span has no leap year (for example 2001/2003) leaves `pcic.day_bins` without Feb 29. Other runs' Feb 29 rows in `subbasin_daily` then have no week, and `load/pcic.sql:40` (`!= 366`) refuses the whole published bundle. Fix: build `pcic.day_bins` from a fixed leap year rather than from the run's period, since `week` does not depend on the period. Alternatively, reject YEARS spans that contain no leap year.

## Checked and found correct

These need no action.

- **Monthly flow against the old code.** The outlet, sub-basin and segment arithmetic is the old arithmetic with `(month)` replaced by `(month, day)`, followed by an `n_days`-weighted period mean. Every step up to the clamp is linear, so the monthly `q_local`, `q_acc` and segment flow equal the old values up to float noise. The clamp and the 5-decimal rounding are still applied per period, in 09. The segment set is identical: weights are inserted for every share, and 09 inner-joins the period table, as the old INSERT did. Each segment carries one group, through `watershed_group_code = :'wsg'` in 07, so `ON CONFLICT` never fires. One residual remains, as the plan already allows: rows whose value sits on a 5th-decimal rounding boundary.
- **The 06 accumulation loop.** `q_acc` starts as `q_local`. `FOR d IN REVERSE maxdepth - 1..0` adds the finished totals of the depth d+1 children to their parents. A child at depth d+1 has its parent at depth d by construction of the recursive tree, and the unreached guard runs before the loop. `maxdepth = 0` gives no iterations, as it should. `1..0` is lexed correctly (PostgreSQL's `numericfail` rule).
- **psql.** `:var` is interpolated after identifier text (`pcic_outlet_:table`, `b.:step`). No psql variable is used inside a `$$` block: values reach DO blocks through temp tables (`run`, `loading`). `\if :weekly` is always given 0/1. `\copy incoming FROM pstdin` is correct under `-f` with piped stdin. The `\copy (... WHERE model = '...' ...)` in `-c` quotes values that were validated beforehand.
- **Shell.**
  - `[ "$WEEKLY" = 1 ] && export_table ...` and `qa="$qa"...$(...)` both still exit on failure. Tested: set -e applies to the final command of the `&&` list and inside the function.
  - `fetch_batch`'s `&&` chain and the 255 returns behave correctly under xargs.
  - The RUN slug for `historical, ssp245` is `..._historical_ssp245_...`.
  - The awk month-day mapping takes each date from the reduced file, so the Feb 29 bin, which carries a different year, maps correctly.
- **Fingerprints.**
  - The CSV round trip of double, ltree and integer[] reproduces the crosswalk `x::text` md5 exactly.
  - The column order of `fwapg.pcic_fwa_crosswalk` (04) matches `pcic.fwa_crosswalk`, so `INSERT ... SELECT *` and the md5 agree.
  - A truncated or failed download fails the row/key/sum check, or `gunzip`'s EOF error (exit 1, measured).
