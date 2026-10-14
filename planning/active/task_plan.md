# Task: FWA_WatershedAtMeasure: exbc CTE missing from non-lake path (xborder regression) (#1)


PR #185 "Xborder" (upstream `smnorris/fwapg`, merged 2026-01-16) removed the `exbc` CTE from the non-lake code path in `FWA_WatershedAtMeasure` but kept the `UNION ALL ... FROM exbc` branch that reads it in the `agg` CTE (`db/schema.sql:3929` at upstream 8b3904e). Going by that PR's notes ("do not load nhd or hydrosheds", "update fwa_watershedatmeasure to use new xborder data"), dropping the CTE looks intended, and the leftover branch is the bug.

**Every non-lake call fails, not only cross-border points.** PL/pgSQL plans the whole `RETURN QUERY` statement, so the undefined `exbc` is an error at any point the non-lake branch handles. Measured 2026-10-12 on a database built from `db/schema.sql` at NewGraphEnvironment/fwapg@b010209 (NewGraphEnvironment/fresh#253's loader run, evidence `fresh/data-raw/logs/docker_load_253/`):

| call | DB from current `schema.sql` | older local DB, loaded before upstream PR 185 |
|---|---|---|
| `whse_basemapping.fwa_watershedatmeasure(360873822, 166030)` (Bulkley, inside BC) | `ERROR: relation "exbc" does not exist` | 231944.7 ha |
| `postgisftw.fwa_watershedatmeasure(360873822, 166030)` | 231944.7 ha | 231944.7 ha |
| `whse_basemapping.fwa_watershedatmeasure(360457111, 924.5)` (lake path) | 11.5 ha | 11.5 ha |

The `postgisftw` copy in `schema.sql` still defines `exbc` in both paths, so only the `whse_basemapping` copy is broken. fresh's `frs_watershed_at_measure()` calls the `whse_basemapping` one.


**Round 2 (this plan):** smnorris asked on smnorris/fwapg#199 for the fix to be redone by removing `exbc`. Scope decided at the plan gate (2026-10-13): **Middle**, which removes every `exbc` CTE and `UNION ALL` branch from both copies of the function. Tables, schemas, `hydroshed()`, `fwa_huc12()` and `postgisftw.hydroshed` stay (upstream #184).

## Phase 1: Upstream branch `watershedatmeasure-drop-exbc` off `upstream/main`
- [x] Branch off `upstream/main` (`8b3904e`, re-fetched first). Commits carry no `planning/`, no NGE issue numbers and no `Claude-Session:` trailer.
- [x] Migration `db/migrations/202610131654__watershedatmeasure_drop_exbc.sql` (via `create_migration.sh`, ts > 202610131450): `CREATE OR REPLACE` of both functions, bodies taken from `upstream/main:db/schema.sql` minus the `exbc` CTEs and branches.
- [x] Same edits in `db/schema.sql` at all four sites, with the lake-path comma fixed. Check: `grep -c exbc db/schema.sql` = 0, and no `hydroshed`/`wbdhu12`/`Huc12` remains inside either function body.

## Phase 2: Test
- [x] Bodies agree: after the migration, `md5(prosrc)` of the two copies is equal (they were equal before #185).
- [x] Areas, with both new functions in a scratch schema on the loaded local DB, at the four points (expected unchanged, because the hydrosheds/NHD tables are empty): Bulkley `(360873822, 166030)` 231944.70; Kootenay R. `(356570348, 160000)` 3469676.93; Kootenay Lake `(356570348, 110000)` 4650676.78 (lake path); Columbia `(356570372, 1203700)` 8743886.64. Plus 12,452.9 km² outside BC at the three cross-border points. Drop the scratch schema.
- [x] Migration path, as in round 1: scratch DB from `upstream/main:db/schema.sql`, then `migrate.sh` applies the migration, records the version, re-runs as a no-op and keeps the function COMMENTs. A second scratch DB loads the new `schema.sql` cleanly. Drop both scratch DBs.
- [x] Record the results in `findings.md`.

## Phase 3: Upstream PR (stops for approval)
- [ ] Push the branch to `origin`. Draft the title and a ~200-word body in `planning/active/upstream_pr.md`: what changed, that it replaces #199 per his reply, the test table. No session link, no upstream issue.
- [ ] **After approval of the text:** open the PR to `smnorris/fwapg` (`--head NewGraphEnvironment:watershedatmeasure-drop-exbc`), then close #199 with a one-line comment pointing to it. Close #199 only once the new PR exists.

## Phase 4: `newgraph` PR
- [x] On this PWF branch (off `newgraph`): `git revert` round 1's two code commits (migration + `schema.sql`), then cherry-pick Phase 1's commits. Check that `git diff watershedatmeasure-drop-exbc HEAD -- db/` is empty.
- [ ] Delete the remote `fix-watershedatmeasure-exbc` once #199 is closed.
- [ ] Update the #1 body: round 2 steps ticked, new upstream PR linked. #1 stays open until upstream merges.
- [ ] `/planning-archive`, then `/gh-pr-push` (`--base newgraph -R NewGraphEnvironment/fwapg`).

## Validation
- [x] Phase 2 checks pass
- [x] `/code-check` clean (branch mode, 3 rounds, ended by an enumeration of 42 claims)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

## Notes from exploration

- `db/schema.sql` has four `exbc` sites. `postgisftw.fwa_watershedatmeasure` (`:1198`): river path CTE `:1454` and branch `:1510`, lake path CTE `:1635` and branch `:1672`. `whse_basemapping.fwa_watershedatmeasure` (`:3630`): river CTE `:3886` and branch `:3942`, lake CTE `:4067` and branch `:4104`. On `upstream/main` the whse river CTE is absent (that absence is the bug).
- Commas differ by path. In the river path `exbc` sits between `cut` and `agg`, so the whole block goes and `cut`'s `),` stays. In the lake path `exbc` is the last CTE, so the comma after `prelim`'s `)` also has to go.
- Between `upstream/main` and `newgraph`, the only `db/` difference is round 1: the migration `202610131450__fix_watershedatmeasure_exbc.sql` plus 16 lines of `schema.sql`.
- `migrate.sh` orders by timestamp and keeps no file checksums. Deleting round 1's file on `newgraph` therefore breaks nothing, even for a DB that has applied it.
- No CI runs on either branch (both workflows are scoped to `main`), so the scratch-DB run is the only migration test.

