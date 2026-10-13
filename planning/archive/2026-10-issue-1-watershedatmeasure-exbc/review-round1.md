# Code review, round 1: fix-watershedatmeasure-exbc (upstream PR candidate)

Reviewed: `git diff upstream/main..HEAD` in the wt-upstream worktree. That is two commits:
d222a91 (the migration) and fc63f79 (the schema.sql hunk), plus their commit messages.

## Findings

- **[fragile]** db/migrations/202610131450__fix_watershedatmeasure_exbc.sql:279-292, db/schema.sql:3885-3899, and both commit messages. The fix assumes the deletion in PR 185 was an accident. PR 185's own commit text points the other way. It says "update fwa_watershedatmeasure to use new xborder data" and "do not load nhd or hydrosheds". It also added `load/fwa_watersheds_xborder_poly.sql`, which inserts the DFO cross-border polygons, with hierarchical codes, into `fwa_watersheds_poly`. `prelim` (FWA_Upstream over `fwa_watersheds_poly`) therefore already picks up the area outside BC. So the maintainer probably meant to remove the hydrosheds/USGS source, and forgot only the `UNION ALL ... FROM exbc` branch in `agg`.
  - **Effect on a standard install today: none.** `load.sh` leaves `hydrosheds.hybas_lev12_v1c` and `usgs.wbdhu12` empty: the local fwapg DB reads 0 rows in each, and the xborder ids were merged into `fwa_watersheds_poly`. The restored CTE returns no rows, so it behaves the same as deleting the dangling branch. I found no runtime failure. `hydrosheds.hydroshed` and `usgs.fwa_huc12` both exist in schema.sql and resolve through the docker `search_path` (`public,whse_basemapping,usgs,hydrosheds`).
  - **Where the results differ:** a DB that still has hydrosheds/WBD loaded. There the non-lake result becomes the union of the DFO xborder polygons and `ST_Difference(hydroshed|huc12, bcboundary)`, so the shape and `area_ha` no longer follow the DFO delineation. That was the behaviour before PR 185, and the lake path and `postgisftw.fwa_watershedatmeasure` on upstream/main still do it.
  - **Why it matters for this PR:** the commit message reads "Restores the CTE as it was before that change". The upstream maintainer may instead want the other fix: drop the `UNION ALL SELECT ST_Difference(exbc.geom, bc.geom) ...` branch from `agg`, and probably exbc from the lake path and the postgisftw copy too. The PR body should name both options rather than present the restore as the only correct fix. On data loaded by `load.sh` the two produce the same output, so either is safe to merge.

## Checked and clean

- The migration's function text is identical to the patched block in schema.sql (diffed after normalising `CREATE OR REPLACE` to `CREATE`). The header (signature, RETURNS TABLE, IMMUTABLE STRICT PARALLEL SAFE) has not changed, so `CREATE OR REPLACE` is valid and keeps the COMMENT and grants.
- The migration matches the `create_migration.sh` / `migrate.sh` contract: filename `YYYYMMDDhhmm__desc.sql`, BEGIN/COMMIT wrapper, plain ASCII, trailing newline. It is the first file in `db/migrations/`. `migrate.sh` uses a lexicographic `>` against `'0'`, so this migration is applied.
- Fresh install from the fixed schema.sql followed by `migrate.sh`: schema.sql creates no `fwapg.db_version`, so migrate.sh bootstraps `'0'` and re-applies this migration. That re-apply is an idempotent CREATE OR REPLACE of an identical body, so it does no harm.
- CI: `test-migration.yml` fires on `db/migrations/*.sql` for PRs into main. It applies the migration to `fwapg-db:main`, whose function is the broken one, and `CREATE OR REPLACE` succeeds there. plpgsql does not resolve table references at create time.
- Leaks: the diff and both commit messages contain no NewGraphEnvironment names, no local paths, no hosts and no private repo names. The commit author is the operator's own identity, which is normal authorship. The `Claude-Session:` trailer is already known to the operator and is not re-flagged here.

Verdict: no bugs or security issues. One intent/fragility note for the PR body.
