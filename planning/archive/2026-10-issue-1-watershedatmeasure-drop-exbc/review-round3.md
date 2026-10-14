# Code-check round 3 (#1): claim enumeration

Reviewer: subagent, read-only. Branch `1-watershedatmeasure-drop-exbc` at 73e6e42; upstream-bound branch `watershedatmeasure-drop-exbc` at 2aad0d4 (`git diff watershedatmeasure-drop-exbc HEAD -- db/` is empty, so the shipped header text is the same on both).

## Mechanism

Rounds 1 and 2 share one assumption: **a statement about "a db" was written from the db that had been tested (or from file names), not from the load era the reader's db is in.** fwapg databases exist in three states that differ in both schema and data:

| era | xborder polys in `fwa_watersheds_poly` | hydrosheds / `usgs.wbdhu12` | `fwa_watersheds_xborder_poly` table |
|---|---|---|---|
| loaded before #185 (3c43bdd~1 `load.sh`) | no | filled | never existed |
| loaded after #185 (3c43bdd and later `load.sh`) | yes | empty | created by `schema.sql`, dropped by `load/fwa_watersheds_xborder_poly.sql` |
| fresh `schema.sql`, not loaded | no | empty | exists, empty |

Round 1: the migration was written from an era-2 db, so it said nothing about era 1. Round 2: the remedy named a file (`load/fwa_watersheds_xborder_poly.sql`) whose input table exists only between `schema.sql` and the end of `load.sh` in era 2. The places the mechanism reaches are every sentence that states what a db contains or what a result equals. Each one is in the table below, checked against the era it holds for.

## Claim enumeration

### (a) Migration header, `db/migrations/202610131654__watershedatmeasure_drop_exbc.sql` lines 1-14

| # | claim | source checked | verdict |
|---|---|---|---|
| a1 | Removes the exbc CTE and its UNION ALL branch from both copies | extracted both bodies; `grep -ciE 'exbc\|hydroshed\|hybas\|wbdhu\|huc12'` on the migration hits only header lines 3, 5, 8; the new body vs the 3c43bdd~1 body is deletions only (48 lines, no `>` lines) | true |
| a2 | Cross-border area comes from the xborder polygons in `fwa_watersheds_poly` (#185) | `load/fwa_watersheds_xborder_poly.sql` INSERTs into `fwa_watersheds_poly`; 3c43bdd added it and its call in `load.sh`; findings "Round 2 results" measured 12452.9 km² outside BC from the new body | true (era 2) |
| a3 | ...so hydrosheds and NHD are no longer read | new bodies contain no `hydrosheds.`, `usgs.`, `FWA_Huc12`, `hybas`, `wbdhu12` | true |
| a4 | #185 removed the CTE from the non-lake path of the whse_basemapping copy | `git show 3c43bdd -- db/sql/FWA_WatershedAtMeasure.sql`: one hunk, -16 lines, the first `exbc AS` (non-lake). `db/sql/postgisftw.sql` not touched by 3c43bdd | true |
| a5 | ...but kept the branch | 3c43bdd~1 lines 343-348 (`UNION ALL ... FROM exbc`) are not in the hunk; upstream/main `schema.sql` whse copy still has them inside `agg` | true |
| a6 | so every non-lake call failed with `relation "exbc" does not exist` | upstream/main body: the non-lake branch is a single `return query` (body line 25) whose `agg` references exbc; error measured in findings line 13 and quoted in #199 | true |
| a7 | xborder polygons that load.sh has inserted into `fwa_watersheds_poly` since #185 | 3c43bdd `load.sh:137-139`; current `load.sh:148-150`; upstream/main `load.sh:145-147` | true |
| a8 | A db loaded before #185 does not have them | 3c43bdd~1 `load.sh` has no xborder step (it loads WBD and hydrosheds at lines 133-167) | true |
| a9 | reload it | a full rebuild (`schema.sql` into an empty db, then `load.sh`) loads the xborder polys. Re-running `load.sh` alone on an existing db fails loudly at `truncate whse_basemapping.fwa_watersheds_xborder_poly` (era 1: never existed; era 2: dropped by the previous load), `set -e` and `ON_ERROR_STOP` stop it | true, if "reload" means rebuild; the wrong reading fails loudly rather than silently |
| a10 | or watersheds that cross the border lose their area outside BC | with exbc gone and no xborder polys, nothing supplies non-BC area | true |

### (b) Upstream-bound commit messages (`upstream/main..watershedatmeasure-drop-exbc`)

| # | claim | source checked | verdict |
|---|---|---|---|
| b1 | ad3815a: drop the exbc CTE and its UNION ALL branch from both copies (whse_basemapping and postgisftw, river and lake paths) | same as a1; the whse river path had only the branch to drop, which the next sentence explains | true |
| b2 | ad3815a: so neither reads hydrosheds or NHD | same as a3 | true |
| b3 | ad3815a: #185 removed the CTE from the non-lake path of the whse_basemapping copy but kept the branch | same as a4, a5 | true |
| b4 | ad3815a: every non-lake call failed with `relation "exbc" does not exist` | same as a6 | true |
| b5 | 2aad0d4: the same edit as the migration | migration bodies equal the `schema.sql` bodies (already verified; extraction here agrees) | true |
| b6 | 2aad0d4: so fresh installs get it too | upstream has no `db/migrations/` and `schema.sql` writes no `db_version` row, so a fresh install reads `schema.sql`'s body (`migrate.sh` would then re-apply 1654, an idempotent CREATE OR REPLACE) | true |
| b7 | Branch hygiene (CLAUDE.md): no `planning/`, no NGE issue numbers, no `Claude-Session:` | `git diff upstream/main watershedatmeasure-drop-exbc --stat`: two files, migration + `schema.sql`; `#185` refers to upstream's PR | true |

### (c) Revert commit f2aba13

| # | claim | source checked | verdict |
|---|---|---|---|
| c1 | Upstream asked for exbc to be removed instead (smnorris/fwapg#199) | #199 comments: owner "Intent was to drop NHD/hydrosheds, they are no longer needed", then "yes please!" to closing and redoing as a UNION ALL delete | true (the proposal was ours, the owner asked for it) |
| c2 | This reverts 627050e and a616f45 | a616f45 (+496, migration) then 627050e (+16, `schema.sql`); `git diff 627050e~1 f2aba13 -- db/` shows only the migration file's removal, and `git diff a616f45 f2aba13 -- db/` the same, so f2aba13 inverts both exactly | true |
| c3 | so that newgraph's db/ matches upstream/main | `git diff upstream/main f2aba13 --stat -- db/` is empty | true |
| c4 | No database has a dependency on the deleted migration file: migrate.sh compares timestamps only | `migrate.sh`: pending = files whose prefix `>` the latest `db_version.tag` by `applied_at`; no per-file record is checked. 1654 is a full CREATE OR REPLACE of both functions, so nothing 1450 did is needed afterwards | true |
| c5 | 202610131654 is later than 202610131450 | string and numeric order | true |

### (d) Upstream PR draft, `planning/active/upstream_pr.md`

| # | claim | source checked | verdict |
|---|---|---|---|
| d1 | Title: Remove exbc from FWA_WatershedAtMeasure | diff | true |
| d2 | Head `NewGraphEnvironment:watershedatmeasure-drop-exbc`, base `main` | local branch exists; not yet pushed to origin (`origin/watershedatmeasure-drop-exbc` unknown) | true once pushed |
| d3 | Replaces #199, as discussed there | #199 thread (c1) | true |
| d4 | #185 dropped the CTE from the non-lake path ... but left `UNION ALL ... FROM exbc` in `agg` | a4, a5; the branch sits in the `agg` CTE (upstream/main body lines ~270-303) | true |
| d5 | every non-lake call failed with `relation "exbc" does not exist` | a6 | true |
| d6 | removes the CTE and its UNION ALL from both paths of both copies | a1 (the whse river path had only the branch; d4 says so the sentence before) | true |
| d7 | so neither reads hydrosheds or NHD | a3 | true |
| d8 | The two bodies are identical again | `diff` of 3c43bdd~1 whse body vs 3c43bdd~1 postgisftw body: identical; the two new bodies are identical | true ("again" holds: they were identical before #185) |
| d9 | a migration plus the same edit in `schema.sql`, so fresh installs work too | b5, b6 | true |
| d10 | Drop the `schema.sql` commit if you'd rather regenerate it | two separate commits, the migration does not depend on the `schema.sql` one | true |
| d11 | The hydrosheds/usgs tables and functions are untouched (#184) | diff touches only the two function bodies; #184 is "discard hydrosheds/nhd data and related query logic", OPEN | true |
| d12 | Tested on a loaded db | findings "Round 2 results": local `fwapg` db, 2,053 xborder polys | true |
| d13 | The geometries are byte-identical to the pre-#185 function | findings: `md5(ST_AsBinary(geom))` equal at 4 points to the db's function (md5 `04ab3875…`). That is the pre-#185 body: upstream/main's postgisftw body = 3c43bdd~1 postgisftw body = 3c43bdd~1 whse body (diffs here empty), and findings records upstream/main's postgisftw copy at `04ab3875…` | true for the tested db; the reason is that its hydrosheds/`wbdhu12` tables are empty (era 2). See note N1 |
| d14 | the migration applies on a db built from `schema.sql` | findings scratch DB A from upstream/main `schema.sql` | true |
| d15 | and re-runs as a no-op | findings: "No pending migrations" | true |
| d16 | Bulkley R. `(360873822, 166030)` 231944.70 | findings table; `test_areas.sql:887` has the same point | numbers true; stream name not re-checked (db needs credentials from this seat, which were not read) |
| d17 | Kootenay R. `(356570348, 160000)` 3469676.93 | same | same |
| d18 | Kootenay Lake `(356570348, 110000)` 4650676.78 | same; refine `LAKE` in findings | same |
| d19 | Columbia R. `(356570372, 1203700)` 8743886.64 | same | same |
| d20 | Closing comment: "#<new>, which removes `exbc` instead" | placeholder to fill | true |

## Findings

No false shipped claim and no bug. Every factual sentence in (a) to (d) checks against code, git history or the round-2 measurements.

## Clean

Notes, not blocking:

- **N1, the last reach of the mechanism (optional wording).** d13 is true for the tested db, and it is true *because* that db's hydrosheds and `usgs.wbdhu12` tables are empty. On a db loaded before #185 the old and new functions differ: that is what the migration header's precondition (a8 to a10) says. The PR drops that qualifier, which #199's own body had ("the same result on a standard load"). The maintainer's db is a standard load and his stated intent is to drop these sources, so this misleads no one who matters here. If you want the sentence to be true independent of the reader's db, add "(hydrosheds/NHD tables empty, as on any load since #185)".
- **N2.** "reload it" (a9) means rebuild into an empty db. Re-running `load.sh` on any existing db fails at its first `truncate` of `fwa_watersheds_xborder_poly`. That behaviour comes from upstream's `load.sh`, not this diff, and it fails loudly.
- **N3.** `db/README.md` says "Do not delete applied migration files". f2aba13 deletes 202610131450 from `newgraph`. c4 shows nothing needs it: 1654 replaces both functions whole, and `migrate.sh` reads only the latest tag. This is a convention conflict, not a defect. It is already accepted by the plan.
