# Code review, round 2 (fwapg#8 branch, extras/pcic_crosswalk)

## Findings

- **[severity: bug]** review_build.sh:31-39 and :64. Rebuilding while the GeoPackage is open in another process (QGIS, before the reviewer has saved anything) passes the guard, and the reviewer's later work is lost or ends up in the wrong database. The guard counts 0 because nothing is saved yet, and `rm -f "$GPKG"` removes the main file but leaves `review.gpkg-wal` and `review.gpkg-shm` (QGIS opens a GeoPackage it can edit in WAL mode). The open process keeps the unlinked inode, so its later saves never reach the new file. When a `-wal` sits beside a file with more than 0 pages, SQLite opens it in WAL mode whatever the file's header says, so a WAL written by path after the rebuild gets replayed onto the new GeoPackage as foreign pages.
  Reproduced on a scratch copy: a Python sqlite3 connection held `w.gpkg` open in WAL mode with nothing written, so the guard returned 0. I then ran `rm -f` and `ogr2ogr` (a new file, header `01 01`), and the held connection wrote `verdict='right'` for review_id 3. The new file read through the leftover `-wal` returns `v = 1, review_id 3 = right`; the same file copied alone returns `v = 0`. `PRAGMA integrity_check` says `ok` on both, so nothing would report it. The guard does see a committed edit sitting in a `-wal`, which I also reproduced: it returns 1 and refuses.
  Fix: before the guard's first read, refuse when `"$GPKG-wal"`, `"$GPKG-shm"` or `"$GPKG-journal"` exists, or when header bytes 18-19 are not `01 01`. Either means the file is open or a writer crashed. Delete the sidecars together with the main file. `lsof "$GPKG"` also catches a reader in rollback mode, which has no sidecar while idle. This is the convention "Restoring a GeoPackage from a copy: refuse sidecars before the first read".

- **[severity: fragile]** review_build.sh:64-69. If a build fails after `rm -f "$GPKG"`, the half-built file stays at the live path. When the first `layer review` fails (for example, `pcic_qa_outlets` is missing), the file has no `review` layer: `ogr2ogr` exits 1 and leaves a 64 KB GeoPackage, which I reproduced with a bad `-sql` against the DB. The next run's guard then refuses a legitimate rebuild with the misleading "holds unreadable filled-in review rows". That direction is safe, but it blocks a rebuild for the wrong reason. A failure at a later layer, or in the checks at :115-127, leaves at the path the README hands the reviewer a GeoPackage that is incomplete or failed those checks, and it looks the same as a good one. Fix: build into a temporary path in `$OUT` and `mv` it over `$GPKG` only after the checks pass. This also means a failed rebuild never removes the previous file.

- **[severity: fragile]** pcic_crosswalk.sh:181-185 vs :192-194. A job whose QA fails exits with the new `pcic_fwa_crosswalk`, `pcic_qa_drainage`, `pcic_qa_following` and `pcic_qa_flow` in place, but `pcic_qa_outlets` and `pcic_qa_candidates` are still the previous successful run's: the rename only happens after QA passes. review_build.sh reads both sets and does not check that they come from one build. Its checks only confirm that every drawn subid has a row in `pcic_qa_outlets`. A review built after a failed run therefore shows candidates, and flags.csv candidate context, from a different build than the strata and placed points, and nothing reports it. Fix: have pcic_crosswalk.sh drop `pcic_qa_outlets` and `pcic_qa_candidates` at the start of a run, so a failed run leaves none, or have review_build.sh refuse when the staging `fwapg.pcic_outlets` exists, which means the last run failed.

## Checked, not findings

- The round-1 guard against filled rows fails toward refusal on every route I tried:
  - A whitespace-only verdict counts as filled (1).
  - An integer 0 written into `note` counts (1).
  - A committed edit held in a `-wal` by an open connection is seen (1).
  - A renamed `review` layer makes ogrinfo exit 1; under pipefail `filled` is empty and the build refuses.
  - An unreadable file refuses.
- The pass toward pass is the rebuild-while-open case above, where nothing is on disk yet when the guard reads.
- No unblinding strings in the GeoPackage: `gpkg_contents` descriptions are empty, and a `strings` search finds no subid, stratum, flag or rank. The review layer's fid order is review_id, which is an md5 order.
- `pcic_qa_following` has a primary key on subid, so the strata cannot duplicate (subid, stratum). Every placed river outlet has a row: 37,293, with 0 missing and 0 measured outlets lacking a placed share.
- The committed design has 119 distinct review_ids, and its md5 matches the GeoPackage's `sample_id`.
- The `flagged` stratum's population includes 5 unplaced (`broken_chain`) outlets, from the gauge flag. The scoring still holds, because every verdict but `right` counts as an error for placed and unplaced alike. It is noted only because the stratum mixes the two.
