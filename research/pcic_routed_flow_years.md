# PCIC routed flow on the FWA year by year: the per-year sub-basin days

**Verified:** 2026-10-27 · **Issues:** NewGraphEnvironment/fwapg#42 (this product), for NewGraphEnvironment/wet#122; builds on #25 (runs, daily climatology, weights) · **Produced by:** `extras/pcic_crosswalk/pcic_crosswalk.sh` with `DAYS=1` for PNWNAmet historical; `days_build.sh`, `pcic_days.py`, `sql/qa_days.sql`, `sql/qa_report_days.sql`; the probes and the build recorded in `planning/archive/2026-10-issue-42-pcic-crosswalk-keep-the-per-year-series/`

Companion to [pcic_routed_flow_periods.md](pcic_routed_flow_periods.md), which covers one climatology for any period. This file covers the years themselves.

## What is kept, and why it is enough

Every day of every year of a model's series, per placed sub-basin (37,667 for PNWNAmet): `q_local`, the flow generated in the sub-basin, and `q_acc`, the flow accumulated at its outlet on the FWA. One parquet file a year, `pcic.subbasin_days.<model>_<scenario>.<year>.parquet` (`subid int32, date date32, q_local float32, q_acc float32`, sorted by `subid, date`, zstd, row groups of 1,000 sub-basins). Nothing per segment is kept: a segment's flow for any day, window or year is the weights applied to these, `greatest(sum(q_acc of upstream_subids) + q_local * share, 0)`, exactly as for the climatology, because every step from outlet flow to `q_local` and `q_acc` is linear and the clamp comes last.

The days come from the hydromosaic NetCDF the job already fetched for the climatology, now kept (`data/nc/<model>_<scenario>/`, 216 files, 7.6 GB for PNWNAmet), so a new period or the days never fetch again.

## The years are the climatology's own arithmetic

Each year runs through `sql/pcic_crosswalk06_daily.sql`, the same file the climatology runs, so a year and the climatology cannot drift apart in method. Two measurements tie them:

- `06_daily` on the climatology reproduces #25's published daily fingerprint exactly (13,786,122 rows, `sum(round(q_acc::numeric, 6))` = 633459324.098216), before and after the change below.
- `sql/qa_days.sql` reads the published files back and checks that their mean over the run's years is the climatology, bin for bin, within float32 rounding.

The float32 tolerance is relative to each value, not to the mean: a stored value is within 2^-24 of its own magnitude, so a bin's mean is within 2^-24 of the bin's mean magnitude. On a losing reach `q_local` changes sign across years, so its mean can sit near zero while its values do not, and a bound keyed to the mean fails there. The check uses `2^-23 × mean|v| + 1e-9` m³/s (the bound wet#122's parity check uses).

What a reader can expect from averaging the files: `pcic.discharge_monthly` is `09(08(subbasin_daily))`; the mean over years and 08's day-weighted mean are linear and commute; the clamp and the 5-decimal round come once, after averaging, in both. So the files reproduce the published monthly flow to about 1e-7 relative, not at 5 decimals row for row. A direct check (README's window query, rewritten for duckdb, on the 1951–2012 climatology as a stand-in file) agreed with the Postgres window query on all 30,037 BULK segments within 1.1e-8 relative.

## What a year costs to build

Measured 2026-10-27 on the 128 GB build machine, on a stand-in year of the real size (the 1951–2012 climatology, 366 days × 48,688 outlets):

| step | time |
|---|---|
| `pcic_days.py rows` over the 216 NetCDF files (17.8 M rows) | 17 s |
| the same piped into COPY, with the primary key | 75 s |
| `06_daily` (538 tree levels), as first written | 259 s |
| `06_daily`, table built sorted with `fillfactor = 50` | 152 s |
| monthly means | 8 s |
| COPY out and the parquet write | 15 s |

The accumulation is one UPDATE per level of the FWA tree of placed outlets (depth 538). As first written it read one page per row: the table was built in hash-aggregate order and every UPDATE moved its row. Built sorted by sub-basin with half of each page free, every update is heap-only and the loop takes 152 s. A closure table (every sub-basin joined to everything above it) is not faster: the closure is 5,383,218 pairs (mean depth 142), about 2 billion rows a year. Years are built four at once, each in tables of its own. Four at once, each year's steps run about twice as slow (rows and COPY 144–147 s, `06_daily` 300–340 s, months 15–17 s, parquet 16–17 s; the first build, 2026-10-27), so the series takes about 2 h 15 min, not the 4 h 20 min of one at a time.

## Layout

`date` against `year` + `doy` (int32) on the stand-in year: 145,275,142 against 145,338,074 bytes. In a one-year file `date` repeats 366 values per sub-basin and encodes to 1.5 MB; the floats are the rest (71.6 and 71.9 MB). The issue's probe, which favoured `year`+`doy` by 1.7 GB, wrote one 63-year file, where `date` has 23,011 values per sub-basin.
