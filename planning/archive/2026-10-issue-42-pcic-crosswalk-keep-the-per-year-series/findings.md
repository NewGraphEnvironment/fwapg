# Findings — PCIC crosswalk: keep the per-year series from the hydromosaic fetch, so segment flow can be read year by year, 1951–2012 (#42)

## Issue context

**If we do it:** flow on an FWA segment can be read for one year, not only as a climatology, over 1951–2012, so a downstream estimate of change over time can weight its donor gauges by what PCIC models at the place and can be scored against PCIC's own years. **If we never do:** every PCIC table here is a mean over years (`pcic.discharge_monthly`, the weekly table, `pcic.subbasin_daily`), and a question about one year at an ungauged segment cannot be put to PCIC at all.

The fwapg half of NewGraphEnvironment/wet#122.

## Context

`extras/pcic_crosswalk/pcic_crosswalk.sh` fetches each batch's daily streamflow from hydromosaic (PNWNAmet `historical`, 1950-01-01 to 2012-12-31, 23,011 steps), reduces it with `cdo ymonmean -selyear,$YEARS` and deletes the daily file (#25). The daily climatology kept as `pcic.subbasin_daily` is 366 day-of-year bins, routed to segments through `pcic.segment_weights`. So a per-year product means fetching PCIC again, once, and keeping something more than a climatology.

## Sizes, measured

Rows from the 37,667 placed outlets (#28) × 23,011 days = 867 M. Bytes per row measured on 2026-10-24 from 8 outlets' PNWNAmet daily series (184,088 days) pulled from hydromosaic and written as parquet with arrow:

| kept per sub-basin | rows | size | where it fits |
|---|---|---|---|
| every day, 1950–2012, float64 snappy | 867 M | 10.3 GB | parquet on S3 |
| every day, float32 zstd | 867 M | 6.8 GB | parquet on S3 |
| every day, float32 zstd, `year` + `doy` ints | 867 M | 5.1 GB | parquet on S3 |
| per-year months | 28 M | 1–2 GB with indexes | Postgres |
| per-year weeks | 121 M | several GB | Postgres, large |
| per-year statistics for a fixed window set | windows × 62 × 37,667 | small | Postgres, but the windows must be known first |

Float32 is enough: hydromosaic serves 17 significant digits of model output and the published tables round to 5 decimals. At S3 Standard ($0.023/GB-month, list price) 7 GB is about $0.16 a month, and about $0.09 after the bucket's 30-day lifecycle rule moves it to Standard-IA; one full read is about $0.60 of egress. The published `discharge/fwa/v1/` tree is 33.2 GB, so the days add about a fifth. The real cost is the one re-fetch: hydromosaic's per-outlet CSV is 0.93 MB, so about 35 GB passes through PCIC's server on the way in (the bulk endpoint's NetCDF should be smaller; not measured), and a routing query per read.

Per segment, days are several times more again, which is why nothing per segment is kept: a segment's value for any year and window is routed on demand from the sub-basin rows, exactly as `pcic.subbasin_daily` is routed today (`greatest(sum(q_acc of upstream_subids) + q_local * share, 0)`).

<details>
<summary>The probe behind the bytes-per-row figures (R, arrow, curl, jsonlite)</summary>

Outlets measured: 4008184 and seven drawn at random from `GET /outlets` (`set.seed(1)`): 5012422, 2003757, 12009703, 5001590, 8008219, 12007176, 206008682. Each outlet's PNWNAmet `historical` streamflow series is the one `GET /outlets/<id>/timeseries` lists with `model == "PNWNAmet"` and `variable == "streamflow"`; its `data_uri` returns a CSV with a 6-line attribute header, then `Time, streamflow (m**3 s**-1)`.

```r
suppressMessages({library(jsonlite); library(arrow)})
base <- "https://beehive.pacificclimate.org/hydromosaic"
dir <- tempfile("hm"); dir.create(dir)
get <- function(p) { h <- curl::new_handle(); curl::handle_setopt(h, timeout = 180)
  r <- curl::curl_fetch_memory(paste0(base, p), h); stopifnot(r$status_code == 200); r }
ids <- c(4008184, 5012422, 2003757, 12009703, 5001590, 8008219, 12007176, 206008682)
for (id in ids) {
  ts <- fromJSON(rawToChar(get(sprintf("/outlets/%s/timeseries", id))$content))
  sel <- ts[ts$model == "PNWNAmet" & ts$variable == "streamflow", ]
  writeBin(get(sel$data_uri[1])$content, file.path(dir, paste0(id, ".csv")))
}
rd <- function(f) { x <- readLines(f); i <- grep("^Time,", x)
  d <- read.csv(text = x[(i + 1):length(x)], header = FALSE, col.names = c("time", "q"))
  data.frame(subid = as.integer(sub("\\.csv$", "", basename(f))),
             date = as.Date(substr(d$time, 1, 10)), q_m3s = d$q) }
fs <- list.files(dir, "\\.csv$", full.names = TRUE)
d <- do.call(rbind, lapply(fs, rd)); d <- d[order(d$subid, d$date), ]
sz <- function(tbl, nm, ...) { f <- tempfile(fileext = ".parquet"); write_parquet(tbl, f, ...)
  b <- file.size(f); cat(sprintf("%-36s %.2f B/row -> %.1f GB\n", nm, b / nrow(d), b / nrow(d) * 37667 * 23011 / 1e9)) }
t64 <- arrow_table(d)
t32 <- arrow_table(subid = d$subid, date = d$date, q_m3s = Array$create(d$q_m3s, type = float32()))
tdoy <- arrow_table(subid = d$subid, year = as.integer(format(d$date, "%Y")),
                    doy = as.integer(format(d$date, "%j")), q_m3s = Array$create(d$q_m3s, type = float32()))
sz(t64, "float64 snappy (default)")
sz(t64, "float64 zstd", compression = "zstd")
sz(t32, "float32 zstd", compression = "zstd")
sz(tdoy, "float32 zstd, year + doy ints", compression = "zstd")
cat(sprintf("raw CSV per outlet: %.2f MB -> %.1f GB for 37,667\n", mean(file.size(fs)) / 1e6, mean(file.size(fs)) * 37667 / 1e9))
```

Output on 2026-10-24 (184,088 rows, 8 outlets): 11.87, 11.15, 7.87 and 5.91 B/row, so 10.3, 9.7, 6.8 and 5.1 GB; raw CSV 0.93 MB per outlet, 34.9 GB for all. Rows scale as outlets × 23,011; the bytes-per-row figure is the only thing the 8 outlets estimate.

</details>

## Options for the plan gate

- **(a) Per-sub-basin days as parquet**, one file per batch or watershed group, published beside the other crosswalk outputs and read with duckdb. Any window, any year, no second fetch ever; nothing new in Postgres. Routing per read costs a query over the upstream sub-basins' days.
- **(b) Per-year months (and weeks) per sub-basin in Postgres**, in the shape of `pcic.subbasin_daily` plus a `year` column. Small, SQL-native, reproduces the monthly table's years exactly; a window that is not month- or week-aligned cannot be read.
- **(c) Per-year window statistics** for a window set passed in as a parameter. Smallest, and ties this repo to a downstream package's window definitions.

Recommendation: (a), with (b)'s months derived from it as the QA check, since the per-year monthly means must average over years to the published 1951–2012 monthly table row for row.

## Checks

- Averaging the kept years reproduces `pcic.discharge_monthly`'s 1951–2012 run row for row (40,524,444 rows, the fingerprint in #25), and `pcic.subbasin_daily` bin for bin.
- Routing lag: the clamp at zero is counted per year, not only per period, since a dry year's rising freshet clamps more mid-network rows than the climatology does.
- One fetch. The script keeps the daily NetCDF, or its reduced form, before any climatology is taken from it, so no later period means fetching again.

Relates to #25, #28, #8, #20, NewGraphEnvironment/wet#122, NewGraphEnvironment/wet#118.



## From the wet session (2026-10-26, cross-session message), for the resume

wet#122's branch `122-pcic-per-year-routed-flow-keep-the-years` (`scripts/departure_pcic.R`, commit 5a67a46 there) already reads the decided layout: `pcic.subbasin_days.PNWNAmet_historical.<year>.parquet` (`subid int32, date date32, q_local float32, q_acc float32`) for 1951–2012, holding each file to its `pcic.series` row (`bytes`, `rows`, `subbasins`, both `floor(double(v)*1000+0.5)` sums) and to the 1951–2012 run's `crosswalk_md5`. Two consequences folded into `task_plan.md`:

1. `pcic.series` names no commit, so wet takes it from `WET_FWAPG_DAYS_COMMIT`; a `commit` column is a pending gate decision (recommended: add it).
2. The `qa_days.sql` tolerance: float32 rounding bounds each value's error relative to that value, so a bin mean's error is bounded by 2^-24 × mean|v|, not by |mean|. On a losing reach `q_local` changes sign across years and the mean can sit near 0 while the values are near 1 m³/s (error about 6e-8), which `1e-6 * greatest(abs(clim), 1e-3)` (floor 1e-9) would fail. The bound is now `2^-23 × mean|v| + 1e-9`, wet's parity bound; not yet measured on real data.

## Resume, 2026-10-27 (UTC)

### The `commit` column (the pending gate decision)

Taken as recommended: `pcic.series` carries `commit text`, `git rev-parse HEAD` at export, and a `DAYS=1` build refuses to start with uncommitted changes under `extras/pcic_crosswalk` or `load` so that the column cannot name a commit the files were not built from. The user was away; this is reversible before merge (drop the column from `load/pcic_schema.sql` and `sql/pcic_export_days.sql`) and is named in the PR for their call.

### Phase 1: a mid-run edit, and the restart

The first `DAYS=1 FETCH_ONLY=1` run (00:10 UTC) was killed at 00:15 after one batch: the job script was edited above the line bash was executing (the `COMMIT` guard), and bash reads a script by byte offset, so after `xargs` returned it would have resumed mid-line in the edited file. Killed cleanly (the `.nc.tmp` downloads were discarded, which is what the tmp-then-move is for) and relaunched from a frozen copy, `data/run42_fetch_frozen.sh`, at 00:16 UTC. The kept batch was reused.

### Phase 2: timing one year, and two changes to the plan's mechanism

Measured 2026-10-27 in a scratch database holding the staging tables (`pcic_fwa_crosswalk` from `pcic.fwa_crosswalk`, `pcic_outlets` from `fwapg.pcic_qa_outlets`, `pcic_subbasins` with `fwa_depth` rebuilt by 06's recursive CTE: 37,667 sub-basins, tree depth 538), on a stand-in year of the real size (the cached 1951–2012 climatology, 366 days × 48,688 outlets), while the fetch ran:

| step | first cut | after the fix |
|---|---|---|
| COPY of 17.8 M outlet rows (from CSV, not yet from `pcic_days.py rows`) + primary key | 70 s | |
| `06_daily` | 259 s | 152 s |
| monthly means INSERT | 8 s | |
| COPY out + `pcic_days.py parquet` | 15 s | |

- **`06_daily` on the climatology reproduces #25's daily fingerprint exactly**: 13,786,122 rows, 37,667 sub-basins, `sum(round(q_acc::numeric, 6))` = 633459324.098216, before and after the fix below. So the 06 split changed nothing.
- **The closure-table contingency is slower, not faster.** The closure of the FWA tree of placed outlets is `sum(fwa_depth + 1)` = 5,383,218 (ancestor, descendant) pairs (mean depth 142, median 101), so a closure join is about 2 billion rows a year, against the loop's 13.8 M row updates. Not taken.
- **What the loop spent its time on:** `EXPLAIN (ANALYZE, BUFFERS)` of one level showed index nested loops, but 48,289 buffer hits to read 47,580 rows: one page per row. The table was built in hash-aggregate order and each UPDATE moved its row to a new page (no free space for a heap-only update). Building `:dst` `ORDER BY subid, month, day` `WITH (fillfactor = 50)` made every update heap-only (10,272,888 of 10,272,888) and cut the loop from 259 s to 152 s. Applied in `06_daily`, so the climatology runs it too.
- **A year still takes about 4.5 min, so years are built at once:** `days_build.sh` (one year: rows, COPY, `06_daily`, months, parquet) works in tables of its own (`pcic_outlet_year_<year>`, `pcic_subbasins_year_<year>`, dropped on exit), and the job runs `DAYS_JOBS=4` of them under `xargs -P`. One code path for the climatology and the years, as planned.
- **Decision 2's size rule:** the stand-in year written with `date` is 145,275,142 bytes, with `year`+`doy` int32 145,338,074: `date` is smaller (its column is 1.5 MB of the 145 MB; the floats are 71.6 and 71.9 MB). Kept `date`. At this size the series is about 63 × 145 MB ≈ 9.2 GB, above the issue's 6.8 GB probe (smooth means may compress differently from single years; Phase 5 measures the real files). 38 row groups of 366,000 rows.

### Phase 3: the catalogue's place in the loads

- `load.sh` runs `load/pcic.sql`, which now fetches `pcic.series.csv.gz`. Until that file is published (Phase 5), `load.sh` would fail at the fetch, so the publish has to precede the merge.
- `pcic_export.sql` also refuses when `pcic.series` holds days built on another crosswalk, as it does for runs, so a crosswalk change cannot leave the catalogue describing files routed on the old one.

### Tests

`pcic_test.sh`: 107 → 154 checks, about 35 s; it now needs `uv`, `cdo` and `ncdump` and says so. The days section builds two synthetic NetCDF files in hydromosaic's layout (`string basin_name(outlet)`, `double streamflow(time, outlet)`, `_FillValue -9999`, gregorian days since 1950-01-01), runs the job's own `reduce_batch` (taken from `pcic_crosswalk.sh` by `sed`) against `pcic_days.py rows`, `06_daily` against hand-computed flows on a PCIC/FWA tree that disagree, `days_build.sh` for three years against hand-computed float32 values, `qa_days.sql` passing and failing (1 L/s on one value of one year; a missing year), `qa_report_days.sql`'s sorted-share clamp count against 09's formula on every mid-network segment (13, 14 and 14 segment-months in the years, 14 in the climatology, which equals 09's own count), and every refusal of `pcic_export_days.sql` and the catalogue in `load/pcic.sql`.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| Job script edited while a run of it was executing | Killed the run before bash resumed reading; relaunched from a frozen copy in `data/` |
| `pcic_days.py rows` printed `np.float64(0.229…)` | numpy 2's repr; format `tolist()` values |
| `means` would have held every year in memory (~20 GB) | Accumulate per calendar-day bin file by file |
| `declare -F name` prints the bare name | Test compares the bare names |

### Phase 1 measured: the fetch

`DAYS=1 FETCH_ONLY=1` for PNWNAmet historical, relaunched 00:15:22 UTC, done 00:40:45 UTC: **25 min 23 s**, including the network step (PCIC pages from cache, `ogr2ogr`, 00_outlets). 244 leaf batches: **216 NetCDF files kept, 7,586,628,940 bytes (7.1 GiB; `du` 7.6 GiB)**, every one holding exactly its batch's outlets (48,688 in all), and 28 outlets with no series in `missing.txt` (as in #25). The fetch log cannot count POSTs (`xargs`' children are not traced), so `fetch_batch` now prints one `fetching <batch> from hydromosaic` line per request for Phase 5's count.

A probe of the kept files first reported 0 leaves: the interactive shell's profile defines `grep` as a function and colours `ls`. The job runs in a clean bash and saw 244; the probe was rerun with `command ls`/`command grep`.

### Phase 2 measured: `pcic_days.py rows` on the real files

`rows 1952` over the 216 files: 17,819,808 rows (48,688 outlets × 366 days) in **17 s**; piped into COPY with the primary key added, **75 s**. With the stand-in's other steps a year is about 75 + 152 + 8 + 15 ≈ 250 s, under the plan's 5-min gate, so the loop is committed as is.

### Code-check round 1 (branch, 2026-10-27)

Four findings (`review-round1.md`), all reproduced on reading; three fixed, one an ordering constraint:

1. `pcic_export.sql` refused a `DAYS=1` rebuild of the model whose catalogue was on an old crosswalk (its remedy could not work). Now, with `-v days=1`, that model and scenario's stale rows are deleted in the export's transaction; other models are still refused.
2. A kept year's file was reused on its path alone and catalogued with this run's crosswalk and commit. Each file now carries `fwapg.crosswalk_md5` and `fwapg.commit` in its parquet metadata; the job rebuilds a kept file routed on another crosswalk; `fingerprint` reports each file's own md5 and commit; `pcic_export_days.sql` refuses a file routed on another crosswalk and takes `commit` per file.
3. The climatology load read `cat $DAILY/*.csv`, which a batch halved since an earlier run could double. It now reads only the current leaf batches' files and stops on a missing one.
4. `load.sh` fails until `pcic.series.csv.gz` is on fresh-bc (403 today): Phase 5 publishes it before the PR.

Mutation: removing the own-model exemption fails "with DAYS=1 the export goes ahead" and "deletes them"; removing the file-crosswalk refusal fails "a file routed on another crosswalk is refused". `pcic_test.sh` 154 → 162.

Consequence for Phase 5: the build launched at 00:44 UTC (commit 8d08a0e) writes files without the metadata. It is kept running for its real-data measurements (#25 fingerprints, per-year timing, `qa_days.sql` on the real files), and a final `DAYS=1` run from the reviewed commit rebuilds every file before the publish.

### Code-check round 2

Four fragile findings (`review-round2.md`), two of them inside round 1's fixes:

1. (inside fix 1) A `DAYS=1` export that dropped this model's stale catalogue rows left `pcic.series.csv.gz` on the old crosswalk beside the new `pcic.runs.csv.gz` until the days step finished; a failed days step would publish a pair `load/pcic.sql` refuses. The catalogue is now also written with the shared tables.
2. `COMMIT` was taken once while the per-year code is re-read for every year; the tree is now re-checked (`same_commit`) before the catalogue. Untracked files are left out of the check on purpose: tracked code reads only tracked files, and the build worktree's `data` symlink is untracked.
3. (inside fix 2) Resume kept a file built by older code at the same crosswalk; a kept file is now rebuilt when its commit is unknown or `days_build.sh`, `pcic_days.py` or `06_daily.sql` differ between its commit and this one.
4. `FETCH_ONLY=1` without `DAYS=1` skipped every batch whose climatology was cached, keeping no NetCDF; it now fetches them and checks they are kept.

### Code-check round 3: the mechanism, and the enumeration that ends the review

Round 3 (`review-round3.md`) named the mechanism behind rounds 1 and 2: the job decides "is this step done?" and "do these two artifacts agree?" by whether a file exists at a name, not by an identity the file carries. Each earlier fix widened one check on one axis. Its four findings, one inside round 2's fix:

1. (inside R2-2) `same_commit` checked only the end state, while the per-year code was re-read for hours. Replaced: the job copies `sql/`, `days_build.sh` and `pcic_days.py` to a temporary directory right after the clean-tree check and runs every step from the copy, so the stamped commit is the code that ran.
2. The catalogue and the files could be published out of step. `extras/README.md` now says to upload only after `PCIC crosswalk complete`, parquet first and the `.csv.gz` files last.
3. Refetched NetCDF left every derived cache in place. A climatology CSV older than its batch's NetCDF is reduced again; a per-year file older than any NetCDF is rebuilt; the comment on how to refetch now says which mode fetches.
4. `sql/pcic_crosswalk06_subbasins.sql` was missing from the code a kept file is checked against. Added.

The enumeration, every cached or published artifact the job reads back or publishes, against what it depends on (round 3's table, re-checked against the code after these fixes):

| artifact | depends on | kept only while | status |
|---|---|---|---|
| PCIC network pages (`data/rivers`, `data/lakes`) | PCIC's network at fetch | present | pre-existing; frozen network by design |
| top-level batch lists | `pcic_outlets` | regenerated every run | handled |
| split children, `.split`, `.missing`, `missing.txt` | the parent's outlets at split time | present | pre-existing; stale only after the network pages are refetched |
| `$NC/<batch>.nc` | model, scenario, batch outlets, a whole transfer | outlets equal the batch's; moved into place after `ncdump -h` | handled; PCIC's data version not tracked, by design (one fetch) |
| `$DAILY/<batch>.csv` | the NetCDF, `YEARS`, `reduce_batch` | newer than its NetCDF; only current leaves read | handled (R1-3, R3-3); `reduce_batch` code changes not tracked, as before #42 |
| per-year parquet | NetCDF, crosswalk, `days_build.sh`, `pcic_days.py`, `06_daily`, `06_subbasins` | md5 equal, code unchanged since its commit, newer than every NetCDF | handled (R1-2, R2-3, R3-3, R3-4) |
| code run | the tree at `COMMIT` | copied once at start | handled (R3-1) |
| `pcic.runs`, run tables | crosswalk, weights | export refusals | pre-existing, handled |
| `pcic.series` (build) | the files, the crosswalk | replaced per model and scenario from the files' own metadata; old-crosswalk rows refused or (own model, `DAYS=1`) deleted | handled (R1-1, R1-2) |
| `pcic.*.csv.gz` | the database at export | rewritten each run; catalogue with the shared tables and after step 6 | handled (R2-1) |
| fresh-bc objects | the local files | uploaded after `complete`, parquet first | procedural (R3-2) |
| consumer `pcic.series` | published catalogue, crosswalk | `load/pcic.sql` refusals | handled |

Nothing in the table is reused on a key that leaves out what it was built from, apart from the two rows marked by design or pre-existing.

### Code-check round 4, and the enumeration re-taken from the code

Round 4 (`review-round4.md`) checked round 3's fixes and the table above. Three findings, one inside round 3's fix, and two wrong verdicts in the table:

1. The days loop removed kept files (code or NetCDF axis) while their `pcic.series` rows stayed, and any later run that printed `complete` re-exported them; the upload loop took every model's directory. The days step now deletes its model and scenario's catalogue rows, and re-exports `pcic.series.csv.gz`, before it touches a file; `extras/README.md` uploads only the directory of the model whose `DAYS=1` run completed.
2. (inside R3-1) `trap 'rm -rf "$CODE"' EXIT` under `/bin/bash` 3.2 turns a failed expansion into exit 0. Both scripts now use the success-flag trap (`ok=1` at the end, otherwise `exit $(( rc ? rc : 1 ))`). Probed under 3.2.57: unbound variable → 1, `false` → 1, success → 0. (A first probe reported 0: its `$?` read the `$(…)` that printed the bash version, not the script.)
3. `load/pcic_schema.sql` was still read from the tree; it is now copied with the rest. `pcic_crosswalk.sh` itself is read as it runs; its comment says not to edit it in place during a run.

The enumeration, re-taken from every write site in `pcic_crosswalk.sh` and `days_build.sh` (`grep` for redirections, `mv`, `touch`, `rm`, `-o`, `export_table`, `CREATE TABLE`, `\copy … TO`), with round 4's missing rows:

| artifact (write site) | kept only while | verdict |
|---|---|---|
| PCIC pages `data/{rivers,lakes}/*.geojson` (tmp, mv) | present | pre-existing; the frozen network every key below assumes |
| `data/{rivers,lakes}.geojson`, `fwapg.pcic_rivers/lakes` | rewritten each run | handled |
| batch lists | regenerated each run | handled |
| `.split`, `.missing`, children, `missing.txt` | present | pre-existing; stale only after the pages are refetched |
| `$NC/<batch>.nc` (`.nc.tmp`, `ncdump -h`, mv) | outlets equal the batch's | handled; PCIC data version by design |
| `${tmp}_day.nc`, `.cdl`, `$out.tmp` | overwritten, removed after use | handled |
| `$DAILY/<batch>.csv` (tmp, mv) | newer than its NetCDF; only current leaves read | handled; `reduce_batch` code not tracked, as before #42 |
| staging `fwapg.pcic_*`, per-year `pcic_*_year_<y>` | rebuilt each run; per-year dropped by the trap | handled |
| `data/qa_drainage.csv`, `data/qa_following.csv`, kept `fwapg.pcic_qa_*` and `pcic_qa_build` | rewritten each run; stamp dropped at start | pre-existing, handled |
| `pcic.*.csv.gz` (tmp, mv) | rewritten each run | handled |
| `pcic.series` rows and `pcic.series.csv.gz` | this model's rows deleted and re-exported before any file is touched; written again from the files' own metadata | handled (R1-1, R2-1, R4-1) |
| per-year parquet (`.tmp`, `os.replace`) | crosswalk md5 equal, per-year code unchanged since its commit, newer than every NetCDF | handled (R1-2, R2-3, R3-3, R3-4) |
| the code a run executes | `sql/`, `days_build.sh`, `pcic_days.py`, `pcic_schema.sql` copied once; the job script not edited in place | handled (R3-1, R4-3); `blue_line_paths.sh` read once, early |
| `$CODE`, the uv script environment | removed on exit; uv's own cache | handled |
| fresh-bc objects | uploaded after `complete`, that model's files first, `.csv.gz` last | procedural (R3-2, R4-1) |
| consumer `pcic.series` | `load/pcic.sql` refusals | handled |

The review ends on this enumeration (four rounds; round 4 found a defect inside round 3's fix, so a quiet round could not end it). Every artifact is reused only on a key that carries what it was built from, except the three rows marked pre-existing or by design.

### Phase 5, first build (commit 8d08a0e, stopped by design)

Launched 00:44:11 UTC from a worktree at 8d08a0e, stopped 02:11 UTC during the per-year step, once the review had changed the file format (the per-file metadata of round 1) so that every file it wrote would be rebuilt. What it established before it was stopped:

- **#25's fingerprints reproduced exactly** (`pcic.runs`, built 01:24:01 UTC): 1951–2012 `monthly_q_sum` 178035348.248310 over 40,524,444 rows and 3,377,037 segments, `daily_q_sum` 633459324.098216 over 13,786,122 rows and 37,667 sub-basins, `crosswalk_md5` b1a710836df2cafea0ef514b7ed1c338 (unchanged). The 06 split and the sorted, half-full `06_daily` table changed nothing.
- `sql/qa.sql` all `t`.
- **0 requests to hydromosaic**: no `fetching … from hydromosaic` line in the log; the run read the kept NetCDF.
- Per year, four at once: rows and COPY 144–147 s, `06_daily` 300–340 s, months 15–17 s, parquet 16–17 s, about 8.6 min a year and 2.15 min of wall time per year at four in parallel (so about 2 h 15 min for 63 years). Alone, a year took about 4.2 min; four at once each run about twice as slow, so the parallel gain is about 2x, not 4x.
- Twelve real years (1950–1961) were written: 144,698,369 to 146,405,560 bytes each, so about 9.2 GB for 63.

A `DROP DATABASE` in `pcic_test.sh` waited 20+ minutes on a checkpoint behind the build's writes: run the tests between builds, not during one.

### Phase 5, final build (commit ea9b199)

`DAYS=1 ./pcic_crosswalk.sh` (defaults) from a worktree at ea9b199, launched 02:13:38 UTC, ended 05:28:41 UTC: **3 h 15 min 03 s**, exit 0, `PCIC crosswalk complete for PNWNAmet / historical / 1951-2012`. Another session's long queries shared the database server for the whole run, so the step times below are slower than the first build's.

- The shared steps up to the days loop took about 59 min; the days loop about 2 h 08 min (first file 03:22:22 UTC, last 05:21:18 UTC); the QA, report and catalogue about 7 min.
- Per year, four at once (63 years): rows and COPY 99–197 s (median 144), `06_daily` 180–432 s (median 291), months 8–24 s (median 14), parquet 9–20 s (median 14).
- **#25's fingerprints reproduced exactly again** (`pcic.runs` built 02:57:31 UTC): `monthly_q_sum` 178035348.248310 over 40,524,444 rows and 3,377,037 segments, `daily_q_sum` 633459324.098216 over 13,786,122 rows and 37,667 sub-basins, `crosswalk_md5` b1a710836df2cafea0ef514b7ed1c338. `qa.sql`: all 83 `|t` lines in the log, no `|f`.
- **0 requests to hydromosaic**: no `fetching … from hydromosaic` line, no `bulk-downloads` in the trace.
- **`qa_days.sql` all `t`** (every calendar day once per year; mean `q_local` and `q_acc` equal to the climatology within `2^-23 × mean|v| + 1e-9`; with `ran_all=1`, the float64 monthly means equal `pcic_subbasins_monthly` to 1e-9). Max deviation: `q_local` 2.13e-5 m³/s, at 0.373 of its bin's tolerance; `q_acc` 8.65e-5 m³/s, at 0.426.
- **63 files, 1950–2012, 9,207,962,213 bytes** (144,698,726 to 146,570,959 each), 866,755,337 rows (37,667 × 23,011). `pcic.series`: 63 rows, one crosswalk md5 (b1a71083…), one commit (ea9b199ea7e8ebc9b61e0f031ec81c7801044acc). The issue's 6.8 GB estimate came from 8 outlets' raw series; the sub-basin `q_acc` of large rivers compresses less.

**Per-year clamp** (`qa_report_days.sql`, mid-network segment-months clamped): the climatology 1,568; the years 1951–2012 range 1,174 to 2,011, median 1,616.5, and 42 of the 62 clamp more than the climatology. Worst: 1974 (2,011), 1984 (1,989), 1983 (1,972). Best: 1968 (1,174), 1998 (1,215), 1973 (1,319). The clamped months are April to June in every year, as in the climatology (the rising freshet on mid-network reaches), with some years adding a few hundred in July (1976: 237; 1996: 265; 2001: 250) or September (1969: 206). So a mean over years of clamped per-year flows is at least the clamped climatology on those reaches, not equal to it: to reproduce the climatology, average the days over the years first and clamp once, as the closure below does.

**Direct closure, BULK** (`closure_bulk.R` in `logs/`; duckdb 1.4.3, R 4.5.2): the 1951–2012 monthly mean of the 62 local files, routed through `pcic.segment_weights`, against `pcic.discharge_monthly`'s 1951–2012 run for BULK: 360,444 of 360,444 segment-months joined, **360,424 equal at 5 decimals**; the other 20 differ by one unit in the 5th decimal (a rounding flip), and no row differs from the published value by more than 7.2e-8 m³/s beyond the 5-decimal rounding (max |q − published| 5.07e-6). 0.4 s.

### Phase 5: the publish and the read-back

- **Parquet** first: the 63 files, 9,207,962,213 bytes, to `s3://fresh-bc/fwapg/extras/` with `aws s3 cp`, 05:30:06–05:51:53 UTC (**21 min 47 s**); every object's size equal to its file (`aws s3 ls`). Auto mode did not refuse the write.
- **`.csv.gz`** then, the 7 files of this build (551,257,265 bytes) in **68 s**; each object's `content-length` equal to its file. Before the upload, the local and published shared tables were compared: `fwa_crosswalk` and `day_bins` identical; `runs` differs only in the 1951–2012 row's `built_at`; `segment_weights` differs in `share` on 29,232 of 3,377,037 rows by at most 7.8e-12 relative, and in the element order of `upstream_subids` on 1,008 more (a rebuild of 07, which this branch does not change, sums and aggregates in another order). Its `pcic.runs` fingerprint (`weights_share_sum` at 9 decimals) is unchanged, so the published 1981–2010 run still loads against it.
- **`load/pcic.sql` from fresh-bc** into a scratch database (postgis and ltree, then `load/pcic_schema.sql`): loaded in 54 s; `pcic.series` 63 rows, 1950–2012, one crosswalk md5, `sum(bytes)` 9,207,962,213, commit ea9b199; both runs in `pcic.runs`.
- **HTTP read-back** (`logs/readback_http.R`, R 4.5.2, duckdb 1.4.3, curl 8.0.0): 1983 over HTTP, rows 13,748,455, sub-basins 37,667, `content-length` 146,385,818, `q_local_sum` 7,607,608,735 and `q_acc_sum` 558,608,867,548, and the file's `fwapg.crosswalk_md5` and `fwapg.commit`, all equal to the published catalogue row; 28.6 s.
- **The README's query, as printed** (`logs/readme_years_query.sql`, extracted from the README; run by `logs/readme_query_http.R` as the README says to from R), against the published files: 1,862,294 rows = 30,037 BULK segments × 62 years, no NA, 8,882 clamped to 0, median 0.0059 m³/s; **201 s** over HTTP.
- The build worktree removed; the 63 files and the NetCDF stay in `extras/pcic_crosswalk/data/` (gitignored).
