# Progress — Publish PCIC crosswalk outputs to fresh-bc and load them in load.sh (#9)

## Session 2026-10-11

- Plan-mode exploration — phases approved by user
- Created branch `9-publish-pcic-crosswalk-outputs-to-fresh` off `newgraph`
- Scaffolded PWF baseline from issue #9 with approved phases
- Next: start Phase 1

- Phase 1: `load/fwa_stream_networks_discharge_monthly.sql` and `load/pcic_fwa_crosswalk.sql` (create if missing, truncate and `\copy` from `fresh-bc/fwapg/extras/` in one transaction), run from a fork-only section of `load.sh`
  - Failing check: scratch DB `fwapg_issue9`, load gives `curl: (22) … 403`, psql exits 3, and the table is rolled back (`to_regclass` NULL)
  - Guard proof: a populated table (1 row) keeps its row after a failed load; with `BEGIN`/`COMMIT` stripped, the same failure leaves 0 rows
- Phase 2: uploaded both files to `s3://fresh-bc/fwapg/extras/`; `head-object` sizes equal the local files (1,701,328 and 219,651,807 B)
  - Infra change opened in NewGraph's infra repo (one prefix added to the bucket's public-read list); `tofu plan`: 0 add, 1 change (the bucket policy gains `fresh-bc/fwapg/extras/*`), 0 destroy. Apply is the user's step
  - `extras/README.md` upload commands now target `fwapg/extras/` (the main-flow tree was not uploaded yet, so nothing moves)
- Phase 3 (partial): baseline `qa_gauge.sh 08EE003` saved to `extras/pcic_crosswalk/data/qa_gauge_08EE003_before9.txt` (gitignored); `bash -n load.sh` clean; filed NewGraphEnvironment/fresh#253 (loader calls removed `db/create.sh`; `FWA_StreamProfile` no longer in `schema.sql`)
- Phase 4 (partial): `extras/pcic_crosswalk/README.md` says where the outputs are published and that `load.sh` loads them
- Policy applied by the user; anonymous `curl -I` at 18:32Z: 200 on both `fwapg/extras/` objects, 403 on `fwapg/dumps/fwapg-20260421-203347.dump`
- Code-check round 1 (`review-round1.md`): one finding, real. Plain `csv header` skips the header unchecked, so a reorder among compatible columns loads silently. Fixed with `with (format csv, header match)` (PG 15+; fresh-db 17.5, docker/db 16)
  - Guard proof (scratch table with `anchor_subid`/`fwa_parent_subid` swapped): with `HEADER MATCH`, `column name mismatch in header line field 3`, exit 3, 0 rows; with plain `HEADER`, exit 0, 48,716 rows, 6,558 of them with the two values swapped
- Phase 3, scratch DB `fwapg_issue9` (create path, empty DB with `ltree` and the schema), 18:33-18:39Z: COPY 48,716 and 40,524,444; fingerprint 40,524,444 | 3,377,037 | 178035348.248310; 7 crosswalk indexes. Scratch DB dropped
- Phase 3, in-place reload into `fwapg` on fresh-db (with `HEADER MATCH`), 18:41-18:47Z: fingerprint identical; index list identical (8; `IF NOT EXISTS` skipped all six secondaries); `qa_gauge.sh 08EE003` byte-identical to the baseline (`data/qa_gauge_08EE003_{before,after}9.txt`, gitignored)
- Code-check round 2 (`review-round2.md`): one finding, inside round 1's fix. `HEADER MATCH` needs a PG 15+ server and the README floor is >13. On 14 the failure comes after the multi-hour load. Fixed with a version check at the top of `load.sh` that stops before loading anything, plus a README note
  - Guard proof: passes on fresh-db (17.5); exit 1 with the bar raised to 180000; exit 1 when the database is unreachable (an empty result fails the test)
  - Enumeration (features the new code uses vs minimum version): CREATE TABLE IF NOT EXISTS 9.1, CREATE INDEX IF NOT EXISTS 9.5, COPY option list 9.0, HEADER MATCH 15, psql `\copy FROM PROGRAM` client 10, `show server_version_num` 8.2; `ltree` from schema.sql. Only HEADER MATCH is above the README floor, and it is guarded
  - Accepted, not fixed: the two files are not checked to come from one build (a partial in-place reload fails loudly with `load.sh` non-zero); `IF NOT EXISTS` on indexes matches names only
