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

## Errors Encountered

| Error | Resolution |
|-------|------------|
