# PCIC crosswalk: keep the per-year series (#42)

## Outcome

The PCIC crosswalk now keeps the hydromosaic NetCDF it fetches (`data/nc/<model>_<scenario>/`), so no later period or product fetches again. With `DAYS=1` it writes the per-sub-basin days of every year of a model's series as one parquet file a year (`pcic.subbasin_days.<model>_<scenario>.<year>.parquet`: `subid, date, q_local, q_acc`, float32, zstd). Each year runs through the climatology's own arithmetic, `sql/pcic_crosswalk06_daily.sql`, split out of 06 and parametrised by table. The files are catalogued in `pcic.series` with fingerprints every reader reproduces bit for bit, and with the crosswalk and commit each file names in its metadata. PNWNAmet historical's 63 years (1950–2012) are published to `fresh-bc/fwapg/extras/` and read back over HTTP. The one pending gate decision, a `commit` column in `pcic.series`, was taken as recommended and is named in the PR for the owner. Three things were learned:

- **A float32 product cannot reproduce the 5-decimal monthly table "row for row".** The check that holds is per-bin equality within `2^-23 × mean|v|`, keyed to the bin's mean magnitude, because on a losing reach `q_local`'s mean can sit near zero while its values do not. Routed, that check reproduces `pcic.discharge_monthly` at 5 decimals on all but rounding flips.
- **Single years clamp more than the climatology.** A mean of clamped years is therefore not the clamped climatology.
- **The code review's mechanism.** The job decided "done" and "agree" from a file's presence at a name, not from an identity the file carries. The fix was per-file metadata, rebuilds keyed to the code's commit and to the NetCDF's age, and the job running from a copy of its code. The review ended on an enumeration of every write site, not on a quiet round.

The durable verdict is in [`research/pcic_routed_flow_years.md`](../../../research/pcic_routed_flow_years.md).

## Measurement

- **Fetch, once** (`DAYS=1 FETCH_ONLY=1`): 25 min 23 s; 216 NetCDF files, 7,586,628,940 bytes; 48,688 outlets, 28 with no series (as in #25).
- **Timing one year** (a stand-in year of the real size, alone): rows 17 s; rows and COPY 75 s; `06_daily` 259 s as first written, then 152 s with the table built sorted at `fillfactor = 50`, which makes every accumulation update heap-only. A closure table would be 5,383,218 pairs (tree depth 538) and was not faster, so the plan's contingency was not taken. Four years at once each run about twice as slow, so the parallel gain is about 2x.
- **`date` against `year` + `doy`** on the timed year: 145,275,142 against 145,338,074 bytes. `date` was kept. The issue's probe favoured `year`+`doy` by 1.7 GB, but it wrote one 63-year file.
- **The final build** (`DAYS=1`, commit ea9b199): 3 h 15 min 03 s, exit 0, with another job sharing the database server. That was about 1 h for the monthly run, 2 h 8 min for 63 years four at once, and 7 min for QA and catalogue. Per year: rows and COPY 99–197 s, `06_daily` 180–432 s, months 8–24 s, parquet 9–20 s; a year's steps took 4.9–10.6 min, median 7.6. The first build (8d08a0e, stopped by design once the review changed the file format) had measured about 8.6 min a year at four at once.
- **#25's fingerprints reproduced exactly**, twice: `monthly_q_sum` 178035348.248310 over 40,524,444 rows and 3,377,037 segments, `daily_q_sum` 633459324.098216 over 13,786,122 rows and 37,667 sub-basins, crosswalk b1a710836df2cafea0ef514b7ed1c338. The 06 split changed nothing. **0 requests to hydromosaic** in either build.
- **63 files, 1950–2012**: 9,207,962,213 bytes, 144,698,726 to 146,570,959 each, 866,755,337 rows. The issue estimated 6.8 GB from 8 outlets' raw series; the product holds two values a row, and large rivers' `q_acc` compresses less. The title's 1951–2012 is the climatology's default `YEARS`; 1950, the model's start-up year, is published too, so the series is whole.
- **`qa_days.sql`**: all `t`. Tolerance `2^-23 × mean|v| + 1e-9` m³/s. Max deviation `q_local` 2.13e-5 m³/s (0.373 of its bin's bound), `q_acc` 8.65e-5 m³/s (0.426).
- **Direct closure, BULK**: the files averaged over 1951–2012 and routed by month give `pcic.discharge_monthly` at 5 decimals on 360,424 of 360,444 segment-months. The other 20 differ by a rounding flip in the 5th decimal; no row is more than 7.2e-8 m³/s beyond the rounding.
- **Per-year clamp** (mid-network segment-months): the climatology 1,568; single years 1,174 (1968) to 2,011 (1974), median 1,616.5, with 42 of 62 years above the climatology. Worst 1974, 1984 (1,989), 1983 (1,972); best 1968, 1998 (1,215), 1973 (1,319). Nearly all fall April to June. This turned an expectation from the issue into a number and put a caveat in the README.
- **Publish**: the parquet first, 63 files in 21 min 47 s, each object's size equal to its file. Then the build's 7 `.csv.gz` files (551,257,265 bytes) in 68 s. Before the upload, the republished `segment_weights` was compared with the published one: they differ in `share` by at most 7.8e-12 relative and in array order, a rebuild's summation order. Its `pcic.runs` fingerprint is unchanged.
- **Loads and read-back**: `load/pcic.sql` from fresh-bc into a scratch database took 54 s (63 catalogue rows). 1983 read over HTTP with R 4.5.2, duckdb 1.4.3 and curl 8.0.0 matched its catalogue row on rows, sub-basins, bytes, both sums, md5 and commit, in 28.6 s. The README's query as printed, against the published files, returned 30,037 BULK segments × 62 years in 201 s.
- **Tests**: `pcic_test.sh` 107 → 162 checks, all pass, 53 s.
- **Review spend**: the plan review plus four `/code-check` rounds, five agents, which is the per-task bound. Three rounds found a defect inside the previous round's fix.

### Wrong turns kept

- The fetch job was edited while it ran. Bash reads a script by offset, so the run was killed and relaunched from a frozen copy. Later builds ran from a worktree, and finally from a copy the job takes of its own code.
- A probe reported "0 leaves" because the shell profile shadows `grep` and `ls`. The job saw 244.
- A trap probe reported exit 0 on a failed expansion. The probe was reading the wrong `$?`; the re-probe showed the success-flag trap works.
- A test run's `DROP DATABASE` waited 20+ minutes behind the build's checkpoint, so tests now run between builds.

## Evidence

`logs/20261027_*`: the final build's trace (database URL scrubbed), the BULK closure, the HTTP read-back and the README query. The scripts that produced them are in `logs/*.R` and `logs/readme_years_query.sql`. The review rounds are in `review-*.md`; the timings and the enumeration that ended the review are in `findings.md`.

Closed by: PR into `newgraph` (opened from this branch after this commit); issue #42 closed by hand after its merge.
