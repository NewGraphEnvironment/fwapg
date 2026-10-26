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
