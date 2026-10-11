## Outcome
The PCIC crosswalk outputs are published, and this fork's `load.sh` loads them. Both `.csv.gz` files from the #14 build are in `s3://fresh-bc/fwapg/extras/`. Two new load files (`load/fwa_stream_networks_discharge_monthly.sql`, `load/pcic_fwa_crosswalk.sql`) create each table if missing, then truncate and `\copy` it from the public URL in one transaction. A fork-only section of `load.sh` runs them.

The issue had decided to make all of `fwapg/` public. Exploration found that `fwapg/` also holds full database dumps, and the bucket's prefix grant covers everything under it. At the plan gate the user narrowed the grant to `fwapg/extras/`. The user applied the policy change in NewGraph's infra repo.

The full fresh-db rebuild the issue asked for was replaced by a load into a scratch database plus a reload over the job-built tables. fresh's loader still calls `db/create.sh`, which upstream removed (NewGraphEnvironment/fresh#253).

Code-check took three rounds. Round 1 found that plain `csv header` skips the header unchecked, so a reordered column loads silently; the fix was `HEADER MATCH`. Round 2 found a problem inside that fix: `HEADER MATCH` needs PostgreSQL 15, and the README floor is 13. `load.sh` now checks the server version before loading anything. Round 3 was clean. The loop ended on an enumeration of every feature the new code uses against its minimum version.

## Measurement
- Fingerprint, identical in the build, the scratch-DB load and the in-place reload: `fwa_stream_networks_discharge_monthly` 40,524,444 rows, 3,377,037 segments, `sum(round(q_m3s::numeric, 6))` = 178035348.248310; `pcic_fwa_crosswalk` 48,716 rows.
- Load time from the public URL on a local Docker database: about 5.5 min for both tables (scratch DB 18:33-18:39Z, in-place reload 18:41-18:47Z on 2026-10-11).
- Upload sizes match the local exports: 1,701,328 B and 219,651,807 B.
- An anonymous request gets 200 on both `fwapg/extras/` objects and 403 on `fwapg/dumps/`.
- The in-place reload left the index list unchanged (8 indexes; `IF NOT EXISTS` skipped all six secondaries), and `qa_gauge.sh 08EE003` output is byte-identical before and after.
- Guard proofs:
  - A failed download leaves the table as it was: 1 row kept, against 0 rows with `BEGIN`/`COMMIT` stripped.
  - With `anchor_subid` and `fwa_parent_subid` swapped in the table, `HEADER MATCH` refuses the load. Plain `HEADER` loads all 48,716 rows, 6,558 of them with the two values swapped.
  - The version guard passes on 17.5. It stops with exit 1 when the threshold is raised and when the database is unreachable.
- Wrong turn kept: the first `HEADER MATCH` control swapped `subid`/`dowsubid` and failed for an unrelated reason (duplicate `-1` in the PK), so it proved nothing. It was redone with a constraint-free swap.

## Evidence
Local and gitignored: `extras/pcic_crosswalk/data/qa_gauge_08EE003_*9.txt`. The reviews are in this directory (`review-round*.md`).

Closed by: PR #22 into `newgraph`
