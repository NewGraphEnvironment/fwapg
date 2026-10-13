# Findings — FWA_WatershedAtMeasure: exbc CTE missing from non-lake path (#1)

## Issue context

## Problem

PR #185 "Xborder" (upstream `smnorris/fwapg`, merged 2026-01-16) accidentally removed the `exbc` CTE from the non-lake code path in `FWA_WatershedAtMeasure`, while keeping the reference to it in the `agg` CTE at line 329.

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

### Fix
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

Work from this repo (`fwapg`), not from link or fresh. Fix option 1 above (restore the CTE): an exact revert of an accidental deletion, the easiest upstream review, and the behaviour already measured to count cross-border area. Option 2 (drop the `exbc` branches) stays with upstream issue 184.

**State to start from (2026-10-12):**
- Branch `fix-exbc-nonlake` (`4708405`, 2026-02-17) already restores the CTE, but in `db/sql/FWA_WatershedAtMeasure.sql`, which upstream deleted when it moved to `db/schema.sql` (upstream PR 193). It cannot be PR'd as is; use it only as the text of the fix.
- Upstream's `db/README.md`: a function change is a migration (`db/create_migration.sh`, `db/migrations/YYYYMMDDhhmm__desc.sql`; CI runs `test-migration.yml` on PRs that change `migrations/*.sql` into `main`). `schema.sql` is **not** updated by migrations; it is regenerated by `pg_dump` "when significant structural changes accumulate". `db/migrations/` does not exist upstream yet, so this would be its first migration.
- So a migration alone leaves fresh installs broken: the documented install is `psql -f db/schema.sql && ./load.sh`, with no `migrate.sh`. (`migrate.sh` creates `fwapg.db_version` if it is missing, so run on a fresh install it would re-apply every migration; harmless for a `CREATE OR REPLACE FUNCTION`.)
- This fork's `main` tracks upstream and takes no commits of ours; the fix reaches it only by pulling upstream after upstream merges.

**Steps:**
- [ ] Branch off `upstream/main` (`8b3904e` or later), not `newgraph`, so the upstream PR carries only this change.
- [ ] Migration `db/migrations/<ts>__fix_watershedatmeasure_exbc.sql`: `CREATE OR REPLACE FUNCTION whse_basemapping.fwa_watershedatmeasure(...)` = the current `schema.sql` body with the `exbc` CTE (above) restored before `agg` in the non-lake path. Take the body from `schema.sql`, not from the old `db/sql/` file, so nothing else regresses.
- [ ] Same edit in `db/schema.sql`, so fresh installs are fixed too. Say in the PR why it is hand-edited rather than regenerated, and offer to drop it if upstream prefers to regenerate.
- [ ] Test without a full load: in a database that has the cross-border polygons, create the fixed function in a scratch schema (`CREATE SCHEMA exbc_test`, the function renamed into it), and run:
  - `(360873822, 166030)` Bulkley: expect 231944.7 ha;
  - `(356570348, 160000)` Kootenay R.: expect 3469676.9 ha, 12452.9 km² outside BC;
  - `(356570348, 110000)` Kootenay Lake (lake path, unchanged): expect 4650676.8 ha;
  - `(356570372, 1203700)` Columbia R.: expect 8743886.6 ha.

  Then confirm the unfixed `schema.sql` text errors (`relation "exbc" does not exist`) in the same scratch schema, so the test can tell the two apart. Drop the scratch schema.
- [ ] Run `migrate.sh --dry-run` against a scratch database to confirm the migration parses and applies.
- [ ] Push the branch to this fork (`origin`) and write the upstream PR title and body as a draft in the PWF, for approval. No PR into this fork's `main`: that branch tracks upstream.
- [ ] **Upstream PR to `smnorris/fwapg` only after the operator approves that specific PR**, from the feature branch (`gh pr create -R smnorris/fwapg --base main --head NewGraphEnvironment:<branch>`), never from `main` (no write to smnorris repos without it). The body pins `8b3904e`, gives the repro (any non-lake point errors on a fresh install), the deleting commit (`3c43bdd`, upstream PR 185), and the test table, and mentions upstream issue 184 as the alternative.
- [ ] **`newgraph` gets the fix through its own PR**, so our databases rebuild with a working function while upstream decides: once the upstream branch is tested, cherry-pick its commit onto a branch off `newgraph` and open a PR with `--base newgraph -R NewGraphEnvironment/fwapg`. Cherry-pick rather than re-edit, so that when `newgraph` later merges upstream's version the two changes are identical and do not conflict. Merging it does not close this issue (`newgraph` is not the default branch); the issue stays open until upstream merges or declines.
- [ ] Afterwards: retire `fix-exbc-nonlake`. Once the fix is upstream, NewGraphEnvironment/fresh can rebuild its local DB with `docker/load.sh` (until then, rebuilding gives a broken `fwa_watershedatmeasure`).

**Not covered here:** the group-shortcut case above (cross-border area dropped where `fwa_watershed_groups_poly` has codes). Measure it before raising it upstream; it may relate to upstream issue 52 ("Do not use watershed groups for upstream analysis").




## Plan-mode exploration (2026-10-13)
- **How upstream handles migrations** (`db/README.md`):
  - A function change is made as a migration under `db/migrations/YYYYMMDDhhmm__desc.sql`. `db/migrations/` doesn't exist upstream yet, so this would be its first migration.
  - CI (`test-migration.yml`) runs `migrate.sh` on PRs into `main` that touch `db/migrations/*.sql`. It runs against the `fwapg-db:main` image, which is postgis plus `schema.sql`, so the migration meets the unfixed function and replaces it.
  - The README also says "Do not hand-edit `schema.sql`". The issue's plan edits it anyway, because without that edit a fresh install stays broken. That edit is a separate commit, so upstream can drop it and regenerate instead. The PR body has to say this.
- **Our databases need the `schema.sql` edit regardless.** The docker db image runs `schema.sql` at init, and fresh's loader builds from `newgraph`'s `schema.sql`. That `schema.sql`, `db/migrations` and `db/migrate.sh` are identical between `upstream/main` and `newgraph`, so both commits cherry-pick cleanly.
- **Fit of the CTE in the current body.**
  - The non-lake path's `ref_point` CTE has `blue_line_key`, `measure_pt` and `geom_pt`, which is what the CTE reads. It goes after `cut`, before `agg`. The text comes from `fix-exbc-nonlake` (4708405).
  - A fresh install has the tables it reads (`hydrosheds.hybas_lev12_v1c` at `schema.sql:4290`, `usgs.wbdhu12` at `schema.sql:4308`), even though they're empty.
  - It also has the functions it calls (`hydrosheds.hydroshed`, `usgs.fwa_huc12`, `fwa_upstreambordercrossings`). `fwa_huc12` is called unqualified, as the lake path already does, and is found through the database `search_path` that `docker/db/search_path.sh` sets.
- **The local database** (`localhost:5432/fwapg`, PostgreSQL 17):
  - It holds the 2,053 cross-border polygons.
  - It has no `fwapg.db_version`.
  - Both of its copies of the function still define `exbc` (it was loaded before PR 185). This is the database behind the issue's expected values.
- **Side details.**
  - `migrate.sh` uses `sorted[-1]`, which needs bash 4.3 or later; the local bash is 5.3.
  - Upstream's `CHANGES.txt` is updated by the maintainer at release, so it isn't touched here.
  - `planning/` doesn't exist upstream, so the upstream branch can't carry any planning files.

## Errors Encountered

| Error | Resolution |
|-------|------------|

## Phase 1–2 results (2026-10-13)

**The fix is an exact revert.** With the 16-line CTE (text from the `postgisftw` copy, `upstream/main:db/schema.sql:1453-1468`) inserted before `-- aggregate the result and dump to singlepart` in the `whse_basemapping` copy (after `schema.sql:3884`), the function body is byte-identical to:
- the `postgisftw` copy in the same `schema.sql`;
- the local DB's `whse_basemapping` body (loaded before PR 185);
- the local DB's `postgisftw` body.

All three are `md5(prosrc)` = `04ab3875b15e4cbf10a413be7acfb1e5`, 18,883 chars, `exbc AS` ×2. The unfixed upstream body is 18,206 chars with `exbc AS` ×1. So PR 185 changed nothing else in this function. `grep -c 'exbc AS' db/schema.sql` goes from 3 to 4. The migration body equals the edited `schema.sql` body (a Python line compare, recorded with the commits).

**Behaviour.** Measured in the local DB (`fwapg`, PG 17.5). The fixed body and the unfixed `upstream/main` body were created as `exbc_test.fwa_watershedatmeasure` and `exbc_test.fwa_watershedatmeasure_unfixed`; only the function name in the header was renamed, so unqualified calls resolve through the DB search_path exactly as in `whse_basemapping`. The schema was dropped afterwards.

```sql
SELECT p.label, w.refine_method, w.area_ha,
  round((st_area(st_difference(w.geom, (SELECT st_union(geom) FROM whse_basemapping.fwa_bcboundary))) / 1e6)::numeric, 1) AS km2_outside_bc
FROM pts p, LATERAL exbc_test.fwa_watershedatmeasure(p.blk, p.meas) w;
```

| call | refine_method | area_ha | km² outside BC | expected (issue) |
|---|---|---|---|---|
| (360873822, 166030) Bulkley | CUT | 231944.70 | 0.0 | 231944.7 |
| (356570348, 160000) Kootenay R. | CUT | 3469676.93 | 12452.9 | 3469676.9, 12452.9 |
| (356570348, 110000) Kootenay Lake | LAKE | 4650676.78 | 12452.9 | 4650676.8 |
| (356570372, 1203700) Columbia | CUT | 8743886.64 | 12452.9 | 8743886.6 |

At the Bulkley point, `exbc_test.fwa_watershedatmeasure_unfixed` raises `relation "exbc" does not exist` (at `RETURN QUERY`, line 26). The four calls took 35 s in total.

The plan review noted this area test is **partly circular**: the fixed body, its callees and the data are the same objects that produced the expected values. That is the point (the fix is a revert to them), but the non-circular evidence is the unfixed body's error together with the md5 equalities.

**Migration path, as CI runs it.** Scratch DB `fwapg_exbc_test` on the local server: `CREATE EXTENSION postgis`, the search_path from `docker/db/search_path.sh`, then `upstream/main:db/schema.sql` loaded with `ON_ERROR_STOP` (rc 0, `exbc AS` ×1 in the `whse_basemapping` body). Run from `db/` with `DATABASE_URL` set inline to the scratch DB:
- `migrate.sh --dry-run` lists the one migration;
- `migrate.sh` applies it (`CREATE FUNCTION`, version 202610131450);
- a re-run reports "No pending migrations".

After that: `exbc AS` ×2, `db_version` = `0,202610131450`, and the function's COMMENT is kept. A second scratch DB loaded with the **fixed** `schema.sql` comes up with `exbc AS` ×2 in both copies. Both scratch DBs were dropped.

**Limits** (from the plan review):
- **An empty fresh install takes the lake branch.** The lake-check subquery returns no row, and `NULL IS FALSE` is false, so neither the error nor the fix shows without data, in CI or here. CI therefore proves only that the migration parses and applies. The repro needs a DB loaded with `load.sh`.
- **No CI runs on the `newgraph` PR or the pushed fork branch.** Both workflows trigger only on `main`, so the local scratch-DB run is the only migration test before the upstream PR.
- **A future upstream migration with an earlier timestamp would be skipped.** `migrate.sh` compares timestamps with `>`, so once 202610131450 is recorded on a `newgraph` DB, such a migration is skipped silently. This is a low risk.
- **The group-shortcut case is not reachable under the current `load.sh`.** `cache.sh` writes `fwa_watershed_groups_poly` without codes, and `fwa_basins_poly` is built from them, so both shortcuts stay empty on a standard load.
