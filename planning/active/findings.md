# Findings — FWA_WatershedAtMeasure: exbc CTE missing from non-lake path (xborder regression) (#1)

## Issue context

## Problem

PR #185 "Xborder" (upstream `smnorris/fwapg`, merged 2026-01-16) removed the `exbc` CTE from the non-lake code path in `FWA_WatershedAtMeasure` but kept the `UNION ALL ... FROM exbc` branch that reads it in the `agg` CTE (`db/schema.sql:3929` at upstream 8b3904e). Going by that PR's notes ("do not load nhd or hydrosheds", "update fwa_watershedatmeasure to use new xborder data"), dropping the CTE looks intended, and the leftover branch is the bug.

**Every non-lake call fails, not only cross-border points.** PL/pgSQL plans the whole `RETURN QUERY` statement, so the undefined `exbc` is an error at any point the non-lake branch handles. Measured 2026-10-12 on a database built from `db/schema.sql` at NewGraphEnvironment/fwapg@b010209 (NewGraphEnvironment/fresh#253's loader run, evidence `fresh/data-raw/logs/docker_load_253/`):

| call | DB from current `schema.sql` | older local DB, loaded before upstream PR 185 |
|---|---|---|
| `whse_basemapping.fwa_watershedatmeasure(360873822, 166030)` (Bulkley, inside BC) | `ERROR: relation "exbc" does not exist` | 231944.7 ha |
| `postgisftw.fwa_watershedatmeasure(360873822, 166030)` | 231944.7 ha | 231944.7 ha |
| `whse_basemapping.fwa_watershedatmeasure(360457111, 924.5)` (lake path) | 11.5 ha | 11.5 ha |

The `postgisftw` copy in `schema.sql` still defines `exbc` in both paths, so only the `whse_basemapping` copy is broken. fresh's `frs_watershed_at_measure()` calls the `whse_basemapping` one.

### Root cause
Diff between `70e19cb` (v0.7.0) and `3c43bdd` (Xborder PR) shows the `exbc` CTE definition (lines 286-299) was deleted from the non-lake path but the reference at line 329 was retained.

The lake path (lines 451-467) still has its `exbc` CTE and is unaffected.

### Fix (round 1, superseded: upstream chose to remove `exbc`, see Plan)
Restore the `exbc` CTE in the non-lake path, identical to the version removed in the xborder PR:

```sql
-- find any upstream contributing area outside of BC (but not including Alaska panhandle)
exbc AS
 (
  SELECT hydrosheds.hydroshed(h.hybas_id) AS geom
  FROM ref_point s
  INNER JOIN hydrosheds.hybas_lev12_v1c h
  ON ST_Intersects(h.geom, s.geom_pt)
  WHERE FWA_UpstreamBorderCrossings(s.blue_line_key, s.measure_pt) IN ('AB_120','YTNWT_60')
  UNION ALL
  SELECT FWA_Huc12(h.huc12) AS geom
  FROM ref_point s
  INNER JOIN usgs.wbdhu12 h
  ON ST_intersects(h.geom, s.geom_pt)
  WHERE FWA_UpstreamBorderCrossings(s.blue_line_key, s.measure_pt) = 'USA_49'
),
```

Upstream PR planned: see **Plan** below.

**Restoring the CTE as written stops the error and adds no area.** It reads `hydrosheds.hybas_lev12_v1c` and `usgs.wbdhu12`, which `load.sh` no longer fills since upstream PR 185 ("do not load nhd or hydrosheds"); both have 0 rows even in the older local DB. Cross-border area now comes from `fwa_watersheds_xborder_poly`, which `load.sh` inserts into `fwa_watersheds_poly` (`load.sh:148-150`, 2,053 polygons, ids >= 1,000,000,000), and the function already picks it up through its fundamental-watershed step (`prelim`).

Measured 2026-10-12 on the older local DB, whose `whse_basemapping` copy still defines `exbc` in both paths and which holds the same 2,053 cross-border polygons. The 113 cross-border polygons under the Kootenay (`wscode_ltree <@ '300.625474'`) total 12,452.9 km²:

| call | path | area_ha | km² outside BC | km² of the Kootenay cross-border polygons in the result |
|---|---|---|---|---|
| `fwa_watershedatmeasure(356570348, 160000)` (Kootenay R., 8 km below the Idaho border) | river (CUT) | 3469676.9 | 12452.9 | 12452.9 |
| `fwa_watershedatmeasure(356570348, 110000)` (Kootenay Lake) | lake | 4650676.8 | 12452.9 | 12452.9 |
| `fwa_watershedatmeasure(356570372, 1203700)` (Columbia R. between Castlegar and Trail, all of KOTL upstream) | river (CUT) | 8743886.6 | 12452.9 | 12452.9 |

The `whse_basemapping` and `postgisftw` copies return identical results at all three points.

So removing the `exbc` branches from `agg` in both paths gives the same area as restoring the CTE, and matches upstream issue 184, which proposes dropping the hydrosheds/NHD logic. Which one is upstream's call.

**One case not tested.** In that DB `fwa_watershed_groups_poly` has NULL `wscode_ltree` / `localcode_ltree` (246 of 246 rows) and `fwa_basins_poly` is empty, so the group and basin shortcuts never fire and every upstream group is assembled from assessment and fundamental watersheds. Where group codes are populated, reading the SQL, a point downstream of a whole group would take the BC-only group polygon (KOTL: 9,369.5 km², none of it overlapping the cross-border polygons) and `prelim` would exclude that group's cross-border fundamentals (KOTL: 12,237.0 km²). Not measured.

**Still present upstream** at `smnorris/fwapg` `8b3904e` (2026-07-13, still main's head on 2026-10-12): in `db/schema.sql` the `whse_basemapping` copy reads `FROM exbc` in the non-lake path (`:3929`), and its only `exbc AS` is in the lake path (`:4051`). No open upstream issue or PR covers it; the closest is upstream issue 184 (drop hydrosheds/NHD logic).

## Plan

**Decision (2026-10-13): remove `exbc`, don't restore it.** On smnorris/fwapg#199, smnorris wrote: *"Intent was to drop NHD/hydrosheds, they are no longer needed."* Asked whether to close #199 and redo the fix by deleting the leftover `UNION ALL`, he replied *"yes please!"* So option 2 replaces option 1.

### Round 2: remove `exbc` (to plan with `/planning-init 1`)

Decide at the plan gate:
1. **Scope.**
   - **Minimal:** only the dangling `UNION ALL ... FROM exbc` in the non-lake path of `whse_basemapping.fwa_watershedatmeasure`.
   - **Middle (recommended):** also remove `exbc` from the lake path and from the `postgisftw` copy, so neither function reads hydrosheds or NHD. Results are the same on a standard load, because those tables are empty.
   - **Full (upstream issue 184):** also drop the hydrosheds and USGS tables, the functions that use them (`hydrosheds.hydroshed`, `usgs.fwa_huc12` and any others) and their schemas. That needs a sweep for callers.
2. **`newgraph`.** It carries round 1 (`13af87c`: migration `202610131450__fix_watershedatmeasure_exbc.sql` plus the restored CTE in `schema.sql`). No database has run that migration yet, so remove it in the same `newgraph` PR that cherry-picks round 2, leaving `newgraph` identical to what goes upstream.
3. **Closing #199.** Close it with a comment pointing to the new PR, once that PR is open. The new PR's text needs the operator's approval before it is posted, as before: short body, no session link, no upstream issue.

Re-measure the four test points (Bulkley, Kootenay R., Kootenay Lake, Columbia) on the new function. The areas should not change, because the hydrosheds and NHD tables are empty.

### Round 1 (superseded): restore the CTE

Work from this repo (`fwapg`), not from link or fresh. Round 1 took option 1 (restore the CTE): an exact revert of the deleted lines, the easiest upstream review, and the behaviour already measured to count cross-border area. The upstream PR body offers option 2 (drop the `exbc` branches, in line with upstream issue 184) as the alternative, and upstream picks.

**State to start from (2026-10-12):**
- Branch `fix-exbc-nonlake` (`4708405`, 2026-02-17) already restores the CTE, but in `db/sql/FWA_WatershedAtMeasure.sql`, which upstream deleted when it moved to `db/schema.sql` (upstream PR 193). It cannot be PR'd as is; use it only as the text of the fix.
- Upstream's `db/README.md`: a function change is a migration (`db/create_migration.sh`, `db/migrations/YYYYMMDDhhmm__desc.sql`; CI runs `test-migration.yml` on PRs that change `migrations/*.sql` into `main`). `schema.sql` is **not** updated by migrations; it is regenerated by `pg_dump` "when significant structural changes accumulate". `db/migrations/` does not exist upstream yet, so this would be its first migration.
- So a migration alone leaves fresh installs broken: the documented install is `psql -f db/schema.sql && ./load.sh`, with no `migrate.sh`. (`migrate.sh` creates `fwapg.db_version` if it is missing, so run on a fresh install it would re-apply every migration; harmless for a `CREATE OR REPLACE FUNCTION`.)
- This fork's `main` tracks upstream and takes no commits of ours; the fix reaches it only by pulling upstream after upstream merges.

**Steps:**
- [x] Branch off `upstream/main` (`8b3904e` or later), not `newgraph`, so the upstream PR carries only this change.
- [x] Migration `db/migrations/<ts>__fix_watershedatmeasure_exbc.sql`: `CREATE OR REPLACE FUNCTION whse_basemapping.fwa_watershedatmeasure(...)` = the current `schema.sql` body with the `exbc` CTE (above) restored before `agg` in the non-lake path. Take the body from `schema.sql`, not from the old `db/sql/` file, so nothing else regresses.
- [x] Same edit in `db/schema.sql`, so fresh installs are fixed too. Say in the PR why it is hand-edited rather than regenerated, and offer to drop it if upstream prefers to regenerate.
- [x] Test without a full load: in a database that has the cross-border polygons, create the fixed function in a scratch schema (`CREATE SCHEMA exbc_test`, the function renamed into it), and run:
  - `(360873822, 166030)` Bulkley: expect 231944.7 ha;
  - `(356570348, 160000)` Kootenay R.: expect 3469676.9 ha, 12452.9 km² outside BC;
  - `(356570348, 110000)` Kootenay Lake (lake path, unchanged): expect 4650676.8 ha;
  - `(356570372, 1203700)` Columbia R.: expect 8743886.6 ha.

  Then confirm the unfixed `schema.sql` text errors (`relation "exbc" does not exist`) in the same scratch schema, so the test can tell the two apart. Drop the scratch schema.
- [x] Run `migrate.sh --dry-run` against a scratch database to confirm the migration parses and applies.
- [x] Push the branch to this fork (`origin`) and write the upstream PR title and body as a draft in the PWF, for approval. No PR into this fork's `main`: that branch tracks upstream.
- [x] **Upstream PR to `smnorris/fwapg`**: posted as smnorris/fwapg#199 (2026-10-13), after the operator approved the text. It sends option 1 (restore the CTE) and offers option 2 (delete the dangling `UNION ALL`, in line with upstream issue 184). It comes from `fix-watershedatmeasure-exbc` (fb52a89, `Claude-Session:` trailer dropped, tree unchanged), and no upstream issue was filed. The body as posted is in `planning/archive/2026-10-issue-1-watershedatmeasure-exbc/upstream_pr.md`.
- [x] **`newgraph` gets the fix through its own PR** (#27, merged 2026-10-13 as 13af87c), so our databases rebuild with a working function while upstream decides: once the upstream branch is tested, cherry-pick its two commits onto a branch off `newgraph` and open a PR with `--base newgraph -R NewGraphEnvironment/fwapg`. Cherry-pick rather than re-edit, so that if upstream takes option 1 unchanged, `newgraph`'s later merge of upstream brings identical changes. If upstream takes option 2 instead, reconcile at that merge: `newgraph`'s `schema.sql` would otherwise keep a CTE nothing reads. Merging it does not close this issue (`newgraph` is not the default branch); the issue stays open until upstream merges or declines.
- [x] Afterwards: retire `fix-exbc-nonlake` (deleted 2026-10-13). Once the fix is upstream, NewGraphEnvironment/fresh can rebuild its local DB with `docker/load.sh` (until then, rebuilding gives a broken `fwa_watershedatmeasure`).

**Not covered here:** the group-shortcut case above (cross-border area dropped where `fwa_watershed_groups_poly` has codes). Measure it before raising it upstream; it may relate to upstream issue 52 ("Do not use watershed groups for upstream analysis").












## Round 2 results

**Edit (Phase 1).** `upstream/main:db/schema.sql` had four `exbc` sites. The removal is a regex script with an asserted match count per site (lake CTE 2, river CTE 1, river branch 2, lake branch 2). The river-path CTE was already gone from the `whse_basemapping` copy, which was the bug. Result: `schema.sql` loses 80 lines, `grep -c exbc` = 0, and the two function bodies are textually identical (a `diff` of the extracted functions, header aside). The migration `202610131654__watershedatmeasure_drop_exbc.sql` holds both functions as extracted from the edited `schema.sql`, with `CREATE` → `CREATE OR REPLACE`.

Upstream branch `watershedatmeasure-drop-exbc` (off `upstream/main` 8b3904e): ad3815a (migration) and 2aad0d4 (`schema.sql`), with no `Claude-Session:` trailer. On this branch they are f2aba13 (revert of round 1's 627050e + a616f45; afterwards `db/` equals `upstream/main`), then the cherry-picks 09f4b71 and 2b06d9b; afterwards `db/` equals the upstream branch.

**Areas (Phase 2).** Local DB `fwapg` (the `fresh-db` container, PG 17.5), the same DB as round 1. Both functions there are the pre-#185 body (md5 `04ab3875…`), it holds 2,053 xborder polygons, and `hybas_lev12_v1c` / `wbdhu12` are empty. Both new bodies were created in scratch schema `exbc_test` and run at the four points, next to the current `whse_basemapping` function. Script: `scratchpad/test_areas.sql`; the schema was dropped afterwards.

| point | refine | area_ha | km² outside BC | geometry = current fn | = postgisftw copy |
|---|---|---|---|---|---|
| Bulkley | CUT | 231944.70 | 0.0 | t | t |
| Kootenay R. | CUT | 3469676.93 | 12452.9 | t | t |
| Kootenay Lake | LAKE | 4650676.78 | 12452.9 | t | t |
| Columbia | CUT | 8743886.64 | 12452.9 | t | t |

"Geometry =" compares `md5(ST_AsBinary(geom))`, so the result is byte-identical to the old body that still had `exbc`, as expected with the source tables empty. The 12 calls took 47 s.

**Migration path (Phase 2).** Run inside the container over its local socket, because a host connection without a password works only for the `fwapg` database (stored credentials were not read). Two scratch DBs, each with postgis and the `docker/db/search_path.sh` search_path:
- A, from `upstream/main:db/schema.sql` (rc 0). Before: `whse_basemapping` md5 `eb39c37c…`, which has `exbc`; `postgisftw` md5 `04ab3875…`. `migrate.sh --dry-run` lists the one migration, `migrate.sh` applies it (two `CREATE FUNCTION`), and a re-run says "No pending migrations". After: both copies md5 `d58003b945f4db09ef722d7f754ff20a`, no `exbc`, COMMENTs kept, `db_version` = `0,202610131654`.
- B, from the new `schema.sql` (rc 0, 0 errors in the load log): both copies are `d58003b9…` with comments, which equals A after migration.
- First run: B's simulation of a `newgraph` DB that had already applied round 1 (version 202610131450) did not run. Its setup failed with `schema "fwapg" already exists`, because `schema.sql` creates that schema. Re-run after the code-check round 1 comment was added, with the migration file as of code-check round 1 and `CREATE SCHEMA IF NOT EXISTS`: the DB reports `Current database version: 202610131450`, `Pending migrations: 1`, and applies 202610131654 (md5 `d58003b9…` in both copies). A re-run of A with that file gives identical results. (The header comment was reworded again in code-check round 2; see below.) (The listed `db_version` order is an artifact of the simulation: its 1450 row was inserted at `now() + 1s`.)
- Both scratch DBs were dropped (0 `fwapg_exbc%` left), and `/tmp/exbc` was removed from the container.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `fe_sendauth: no password supplied` creating scratch DBs from the host | Ran the scratch-DB test with `docker exec` inside the container (local socket) |
| `ls` wrapper coloured the migration filename, so `$(ls ...)` gave a bad path | Use the literal path / glob, not `ls` output |

## Code-check (branch, base `origin/newgraph`)

- **Round 1** (`review-round1.md`): no SQL bugs; one fragile finding, accepted and fixed. On a db loaded before #185, with hydrosheds and NHD filled and no xborder polygons, the migration silently drops area outside BC. Fixed with a comment in the migration naming the precondition (`load/fwa_watersheds_xborder_poly.sql`), folded into the upstream migration commit before the push (now ad3815a) and re-picked here.
- **Round 2** (`review-round2.md`): no bugs. It found one defect **inside round 1's fix**: the comment's remedy, "load `load/fwa_watersheds_xborder_poly.sql` first", cannot run on a db from before #185. That file only copies from the staging table `fwa_watersheds_xborder_poly`, which `load.sh` fills with ogr2ogr, and no schema before #185 creates that table (`git grep -c xborder 3c43bdd~1 -- db/` gives 0 files). Reworded to "reload it", which is what actually works, and folded into the migration commit again (upstream ad3815a, here 09f4b71).
- **Round 3** (`review-round3.md`): asked for the mechanism and an enumeration. **Mechanism:** each fix described "a db" from the one that was tested, not from the load era the reader's db is in. There are three eras: before #185 (hydrosheds/NHD filled, no xborder polygons), after #185 (xborder polygons in, hydrosheds/NHD empty, staging table dropped), and a fresh `schema.sql`. **Enumeration:** 42 factual claims across the migration header (10), the upstream commit messages (7), the revert message (5) and the PR draft (20). Every one was checked against code, git history, the #199 thread or these measurements, and all are true. The loop ends on this enumeration. Notes: N1 was applied, adding the condition behind "byte-identical" to the PR draft ("its hydrosheds/NHD tables are empty, as on any load since #185"). N2 is accepted: "reload" means a rebuild, because re-running upstream's `load.sh` on an existing db fails loudly at a `truncate`, which is upstream behaviour. N3 is accepted: deleting round 1's migration, which the plan had already settled.
- **Final re-test**, with the migration file as shipped (`cmp`-identical on both branches): scenario A (upstream `schema.sql`, then migrate, then a no-op re-run) and scenario B (new `schema.sql`; a DB at 202610131450 picks up 202610131654) both give md5 `d58003b9…` in both copies, with no `exbc`, COMMENTs kept, and 0 load errors.
