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
