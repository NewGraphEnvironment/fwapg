# Code review, round 3 (fwapg#8 branch, extras/pcic_crosswalk)

## The mechanism

**A name stands in for provenance and ownership.** Each script finds an artifact by a fixed
path or table name. It then assumes two things about whatever sits at that name: that this
build produced it (or the same build as everything else it reads), and that nobody else
holds it. Nothing records which run wrote a file or table, so neither assumption is ever
checked. Where a guard was added, it checks the state **once**, at a single moment, and for
one route by which the assumption can break. The four earlier findings are all this:

- R1: the same draw meant the same file, which meant safe to delete.
- R2: no rows saved meant nobody had it open. A path being absent meant its WAL was absent.
- R2: the path the reviewer gets meant a finished build.
- R2: `pcic_qa_*` meant the same build as `pcic_fwa_crosswalk`.

## Where the mechanism reaches

### Files and tables the scripts write, replace or delete

| place | guarded? |
|---|---|
| `data/review/review.gpkg`, replaced by `mv` (review_build.sh:152) | **partly**. Lines 41-58 check for sidecars, an open handle, the WAL header and filled rows, but only at the start. Nothing re-checks between that guard and the `mv`, which comes after the whole build. See finding 2. |
| `data/review/review.gpkg-wal`, `-shm` and `-journal` | **no, when `review.gpkg` is absent**. The sidecar loop sits inside `if [ -e "$GPKG" ]`. See finding 1. |
| `data/review/review.building.gpkg` and its sidecars (`rm -f`, :86) | yes. The script owns this name, and nothing else writes it. |
| `review/sample_design.csv` (`cp`, :69) | yes. `cmp` refuses a different draw. On a first build it is written before the build checks run, but a later run with a fixed draw would then be refused, so it fails toward refusal. |
| `data/review/sample_design.csv` (`\copy`, :62) | no. It is overwritten **before** the design guard. After a refused new draw, the copy "beside the GeoPackage" no longer matches it. That is harmless: `review_score.sh` refuses the pair because the md5 does not match. |
| `data/review/flags.csv` (:115) | no. It is written before the build checks, so a build that fails at :137-149 leaves the new flags beside the old GeoPackage. The consequence is small: the design guard has already passed, so `review_id` maps to the same subids, and only values such as `candidate_rank` or the flow ratio can differ. |
| `fwapg.pcic_review_strata`, `_design`, `_rivers` and `_lakes` | yes. The script owns these names (accepted tradeoff). |
| pcic_crosswalk.sh:192-194: `DROP` of `pcic_qa_outlets` and `pcic_qa_candidates`, then `RENAME` | yes. This runs only after QA passes. A failure between the two `RENAME`s leaves `pcic_qa_candidates` missing, so review_build fails, which is the refusal direction. |
| review_score.sh and review_test.sh | yes. They write only to a `mktemp -d` directory. The md5 ties the GeoPackage to its design. |

### Tables and files read on the assumption they come from one build

| place | guarded? |
|---|---|
| `pcic_qa_drainage`, `pcic_qa_following`, `pcic_qa_flow`, `pcic_fwa_crosswalk` after a **failed** job | yes. The job writes all of them while `fwapg.pcic_outlets` exists, so the :31 guard catches them. |
| `pcic_qa_outlets` and `pcic_qa_candidates` against the crosswalk after a failed job | yes (the :31 guard). |
| `fwapg.pcic_qa_gauges`, read by review_sample.sql:82 and review_build.sh:121 | **no**. qa_gauges.sh writes it, and a crosswalk rerun neither replaces nor invalidates it. See finding 3. |
| `pcic_fwa_crosswalk`, replaced by `load.sh` or `load/pcic_fwa_crosswalk.sql` (TRUNCATE, then reload from the published CSV) | **no**. `pcic_outlets` is absent, so the guard passes, while every `pcic_qa_*` table is local. See finding 4. |
| `data/rivers.geojson` and `data/lakes.geojson`, read at :74-77 | no, but the risk is low. The job's step 1 rewrites them before `pcic_outlets` exists. They differ from the build only when the page cache was refetched and the run then failed before step 00 finished. |
| `fwapg.blk_paths` | yes. It is built from the FWA alone, and rebuilt inside the job while `pcic_outlets` exists. |

## Findings

- **[severity: bug]** review_build.sh:41-44. The sidecar check runs only `if [ -e "$GPKG" ]`. When the main file is gone and its `-wal` and `-shm` are left at the path, the build `mv`s a fresh file in beside them, and SQLite replays the leftover WAL onto it. This is R2's replay, reached by a route the R2 fix skips.

  The script points people to this route. After a QGIS crash, or with QGIS still open, the next run says "`review.gpkg-wal exists: close review.gpkg in QGIS first`". The obvious way out is the one the filled-row message itself gives: move `review.gpkg` aside, or delete it. That moves the main file and leaves the `-wal` behind, so on the rerun the guard sees no `$GPKG` and checks nothing.

  Reproduced in a scratch copy of the real `review.gpkg`:
  1. Opened it in WAL mode, set review_id 3 to `right`, and left the WAL uncheckpointed (a crash).
  2. Ran `mv review.gpkg aside.gpkg`, then copied a pristine build into `review.building.gpkg` and `mv`'d that to `review.gpkg`.

  Result: through `ogrinfo`, the **new** file reports 1 filled row, which is the foreign answer. `aside.gpkg` reports 0, because the reviewer's saved answer lives only in the `-wal` it left behind. One rebuild therefore loses an answer from the review moved aside and puts a foreign one into the new review. Neither shows anything wrong. If QGIS opens the new file before anything else does, it checkpoints the foreign page in permanently.

  Fix: move the sidecar loop above `if [ -e "$GPKG" ]` so it always runs. The `mv` at :152 is a copy-back, so it needs the convention "Restoring a GeoPackage from a copy … delete them before the copy-back" whether or not a main file exists. Refuse rather than delete, because a stray `-wal` may hold the only copy of someone's answers.

- **[severity: fragile]** review_build.sh:41-58 against :152. The open-handle, sidecar, WAL-header and filled-row guard runs once, before the build. The `mv` runs after it: after `review_sample.sql`, two `ogr2ogr` loads of `rivers.geojson` (160 MB) and `lakes.geojson` into PostGIS, nine layer exports and the checks. I did not measure how long the build takes. If the reviewer opens the existing `review.gpkg` in QGIS inside that window, which is likely when they are waiting to start, the `mv` swaps the inode underneath it. QGIS's later saves go to the unlinked file, and its `-wal` and `-shm` sit beside the new one. That is exactly R2's failure, reached through a timing window rather than a missing check. Fix: put the guard in a function, call it at the top as now, and call it again immediately before `mv "$NEW" "$GPKG"`. That narrows the window to milliseconds.

- **[severity: bug]** review_sample.sql:80-83 and review_build.sh:121 read `fwapg.pcic_qa_gauges`. Only `qa_gauges.sh` writes that table. `pcic_crosswalk.sh` neither drops it nor replaces it, and the R2 guard tests only `fwapg.pcic_outlets`. After a crosswalk rebuild that **succeeds** but is not followed by `qa_gauges.sh`, the `flagged` stratum and the `gauges` column of `flags.csv` silently use the previous build's FWA flows, `fwa_over_pcic` and `any_pcic_matches_fwa`. The draw changes with them, and nothing reports it.

  This has already happened in this database. `data/qa_gauges.csv` dates from 2026-10-11 10:51, and qa_gauges.sh rewrites it on every run. The crosswalk was rebuilt at 2026-10-12 06:56 (`data/run8.log`), and the committed sample was drawn at 07:15. So the committed draw used gauge flags from the earlier build. It is unaffected **only by luck**: the two builds' sorted outputs are byte-identical (both `.csv.gz` files match `data/before8/sorted.md5`), and none of the 604 gauge rows' `pcic_crosswalk_flag` values differ from the current crosswalk.

  Fix: have `pcic_crosswalk.sh` run `DROP TABLE IF EXISTS fwapg.pcic_qa_gauges` when it starts, so that a review build cannot run until `qa_gauges.sh` has been rerun against this build. The README already prescribes that order.

- **[severity: fragile]** review_build.sh:31. The provenance guard detects only an unfinished job. `load.sh` (via `load/pcic_fwa_crosswalk.sql`) truncates `whse_basemapping.pcic_fwa_crosswalk` and reloads it from the published S3 CSV, and it does the same for the discharge table. It leaves the local `pcic_qa_outlets`, `_candidates`, `_following`, `_drainage` and `_flow` from whichever build was last run here. `fwapg.pcic_outlets` is absent, so the guard passes, and the review mixes the published placements with the local candidates and flags. A cheap cross-build check is already in the data. In this database, every placed crosswalk row whose `candidate_rank` is not NULL has a `pcic_qa_candidates` row at `(subid, candidate_rank)` with the same `blue_line_key`: 37,666 of 37,667. The one exception is subid 5014089, where `crosswalk06` nulls the rank by design. Separately, `count(pcic_qa_outlets) = count(pcic_fwa_crosswalk)` (48,716 = 48,716). Refusing when either check fails would catch a crosswalk from another build. It cannot catch stale gauges, which is finding 3.

## Round-2 fixes, checked

- Staging-table guard (:31). This is correct for a failed job. If `psql` fails, the output is empty, which is not `t`, so the script refuses with a misleading message. That is the refusal direction. Its reach is narrower than its comment claims; see findings 3 and 4.
- Build to a temp file, then `mv`. This is correct: the first `layer` creates the file and later layers pass `-update`; a failure before :152 leaves the live file as it was; and the `mv` is a same-directory rename. The gaps are the timing window (finding 2) and the files written before the checks (`flags.csv` and `data/review/sample_design.csv`, in the table above; both low consequence).
- `od` header check. This is right for files GDAL writes (`01 01`). A file too short to have a header gives an empty `mode`, and the script refuses.
- The filled-row count under `pipefail` with `|| filled=`. An unreadable file refuses, as R2 verified.
- `lsof` is skipped when it is not installed, which is the pass direction. This is acceptable on this machine.

Not findings: `review_score.sh` reads through GDAL, so it sees edits held in a WAL. The leak check covers every layer. The review layer's fid and `review_id` order is an md5 order. Every `review_id` the design draws is checked to be present, so a subid missing from `pcic_qa_outlets` fails the build.
