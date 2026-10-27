# Code-check round 1: branch 42-pcic-crosswalk-keep-the-per-year-series (base d6e45c2)

## Checklist read

- code-check-python.md: in full.
- code-check-infra.md: in full.
- code-check.md: index in full; the prose of all 14 H3s under `## Mechanisms` (evidence blocks and `|` rows skipped). From "Rules that stand alone" and Security, index lines only (none names a tool this diff uses beyond what the mechanisms cover). About 30 other headings not read in full.
- code-check-shell.md: index in full; read in full: "Parallel writers sharing one output file interleave mid-record", "psql does not interpolate `:'var'` inside a dollar-quoted string...", "A second `trap … EXIT` replaces the first" (incl. the bash 3.2 EXIT-trap exit-0 paragraph, probed below), "Put cleanup on the EXIT trap, not RETURN", "A Python CLI redirected to a log...", "`for x in $(cmd | grep … || true)`...", "Empty arrays under `set -u` on bash 3.2", "`cmd dir/*` dies on ARG_MAX", "A verification command can be shadowed...". About 65 headings not read in full.
- code-check-r.md: index in full; read in full: "Postgres row order is never fixed unless the query fixes it...", "A range total taken as the difference of two large running totals...", "An `information_schema` lookup by the literal table name...". About 125 headings not read in full (R-language rules; no R in the diff).
- code-check-spatial.md: index in full; read in full: "Test HTTP range support by a 206...", "THREDDS NCSS returns one time step...". About 130 headings not read in full (terra/sf/GDAL; not used by the diff).

Probes run (no access to database `fwapg`, the run42 worktree, or any `data/`):
- `pcic_days.py` parses under Python 3.11.11 (its `requires-python` floor).
- `/bin/bash` 3.2.57: `set -euo pipefail` plus an EXIT trap ending in `|| true` still exits 1 on a failed pipeline, so `days_build.sh`'s trap does not mask failures (its only pre-trap expansion, `$DATABASE_URL`, sits above the trap).
- The full `pcic_test.sh` in a `git archive HEAD` copy (databases renamed `pcic_rv_test`, `pcic_rv_load`, `pcic_rv_days`), with one probe added: 155 ok, `all pcic tests pass`, 00:54:55 to 00:56:40 UTC. The probe is under finding 1.
- `curl -I` of fresh-bc: `pcic.runs.csv.gz` 200, `pcic.series.csv.gz` 403 (finding 4).

## Findings

- **[fragile] extras/pcic_crosswalk/sql/pcic_export.sql:52-57.** The new `pcic.series` check has no exemption for the model and scenario being rebuilt. The `pcic.runs` check above it exempts the run's own key; this one does not. Its remedy, "rebuild them (DAYS=1)", therefore cannot work. After any crosswalk change, a `DAYS=1` rebuild of the same model and scenario stops at `pcic_crosswalk.sh:373`. That is after the fetch, placement, weights and periods (about 1 h), and before the days step that would replace the rows. Probe: in the test copy, a `pcic.series` row for `PNWNAmet/historical` with `crosswalk_md5 = 'x'`, then `export_run PNWNAmet 1981-2010 0`, is refused with "pcic.series were built on another crosswalk". The only route that works is deleting the rows by hand. Fix one of two ways. Either pass `:days` to `pcic_export.sql` and, when it is 1, exclude (or delete in the same transaction) the series rows of `(:model, :scenario)`, which `pcic_export_days.sql` replaces. Or make the message name only the deletion. A deletion leaves finding 2's stale files in place, so the message should also say to remove `data/days/<model>_<scenario>/`.

- **[bug] extras/pcic_crosswalk/pcic_crosswalk.sh:408-416, with sql/pcic_export_days.sql:57-61.** A year whose parquet file exists is reused on the strength of its path alone. Nothing ties the file to the crosswalk or the commit that built it. Yet the catalogue stamps every file with this run's `crosswalk_md5` and `COMMIT`. Two consequences:
  - **Wrong crosswalk.** `data/days/<MS>/` is per model and scenario, not per crosswalk. After a placement change, kept files built on the old crosswalk are catalogued as built on the new one. For years inside `YEARS`, `qa_days.sql`'s mean check fails, though without naming stale files as the cause. Years outside `YEARS` are checked by nothing except the row and sub-basin counts in `pcic_export_days.sql`: 1950 by default, and 31 more years (1950-1980 and 2011-2012) with `YEARS=1981/2010`. So a same-count stale file there is published under the wrong `crosswalk_md5`.
  - **Wrong commit.** The column records the wrong commit in the normal case, not only an edge one. The guard at lines 41-46 forces a commit before any `DAYS=1` run. So the usual sequence (a run fails, a fix is committed, the run resumes) catalogues every kept year under the new HEAD. That contradicts `findings.md`'s stated purpose for the guard, "so that the column cannot name a commit the files were not built from". This is the "Provenance, and repair" and "Written data outlives the fix" shape.
  - **Fix.** Write `crosswalk_md5` and `commit` into each file's parquet key-value metadata in `pcic_days.py parquet`. On resume, treat a file whose metadata differs from this run as not kept. Have `fingerprint` emit the file's own commit, so `pcic.series.commit` is per file. Alternatively, refuse to resume when any kept file's metadata differs.

- **[fragile] extras/pcic_crosswalk/pcic_crosswalk.sh:186-224 with 273.** The split markers moved to `data/series/<MS>/`, while the climatology CSVs stay in `data/daily/<run>/`. The load at line 273 is still `cat "$DAILY"/*.csv`, so a parent's and its children's CSVs can now sit together in `$DAILY`. Two ways this happens:
  - **Old caches.** With the pre-change caches (CSVs from #25, no `.nc`, `.split` markers left in the abandoned `data/series/<run>/`), a batch that #25 halved for repeated non-422 failures is fetched as a whole again. If it now succeeds, the parent's CSV lands beside its old children's.
  - **Kept `$DAILY`.** If `$DAILY` is kept while the `.nc` files are absent (pre-change caches, or after the README's "remove $NC and $SERIES to fetch the model and scenario again"), a `DAYS=1` run refetches every batch. A batch over 50 outlets that hits repeated 502s or truncated files is then halved, and its children's CSVs are written beside the parent's existing one (line 190 returns early only when `DAYS=0`).

  Either way, `\copy fwapg.pcic_outlet_daily` fails on its primary key right after the fetch. It is loud, but the error does not point at the cause, and it contradicts the plan's statement that existing `data/daily/<run>/` caches "stay valid". Fix: load only the current leaves' CSVs, e.g. `for f in $LEAVES; do cat "$DAILY/$(basename "$f" .txt).csv"; done | $PSQL -c "\copy ..."`. A missing CSV should be an error. This also keeps stale CSVs of an old batch composition out.

- **[fragile] load/pcic.sql:30 (via load.sh:189).** `load/pcic.sql` now fetches `pcic.series.csv.gz` with `curl -sSf`, inside the one transaction. At review time fresh-bc answers 403 for that object (`pcic.runs.csv.gz` answers 200), so every `load.sh` and `load/pcic.sql` run fails until it is uploaded. Phase 5 publishes before the PR, but nothing enforces that order. Upload `pcic.series.csv.gz` (header-only is fine; `load/pcic.sql` accepts an empty catalogue) before this merges into `newgraph`.

## Not findings (checked)

- `06_daily`: the dollar-quoted depth loop takes its table through `set_config`/`current_setting`, the psql-interpolation trap the rule names. Four concurrent runs touch only their own `:src`/`:dst`. Shared tables are read-only, with no ANALYZE or DDL on them.
- `days_build.sh` under `xargs -P 4 -I {}`: two arguments carry `{}`, well within BSD xargs' limit of 5. A failing year makes xargs exit 123, which stops the job under `set -e`. The months INSERT before the parquet write is harmless, because the table is rebuilt on every run.
- `pcic_days.py parquet`: the count check (`n == nsub * ndays`, no duplicate `(subid, date)`) implies every sub-basin has every day. The `fingerprint` sum is exact in int64. In Postgres the float8 sum is exact below 2^53, which the realistic totals (about 1e12) are.
- `qa_days.sql`'s tolerance (2^-23 times the mean magnitude, plus 1e-9) covers float32 rounding plus the float64 path differences: ncdump's printed precision, and summation order in the depth loop. The `\copy ... TO STDOUT` without ORDER BY is sorted in `parquet`.

/Users/airvine/Projects/repo/fwapg/planning/active/review-round1.md
