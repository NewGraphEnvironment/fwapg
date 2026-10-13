# Code-check round 2: fix-watershedatmeasure-exbc + upstream PR draft

Reviewer: subagent, 2026-10-13. Scope: `upstream/main..fix-watershedatmeasure-exbc` (d222a91, fc63f79) at worktree `wt-upstream`, and `planning/active/upstream_pr.md` from **Title** down.

## Clean

I found no bugs, security issues or factually wrong published claims.

## What was checked, and how

**Code**
- The migration body is byte-identical to the patched `schema.sql` whse_basemapping function. I diffed the extracted function text, header included, after normalising `CREATE OR REPLACE` to `CREATE`. Header attributes (`plpgsql IMMUTABLE STRICT PARALLEL SAFE`, RETURNS TABLE) are unchanged.
- The patched whse_basemapping function equals the postgisftw copy except for the schema name.
- md5 of prosrc, computed from the files:
  - migration, patched whse_basemapping and postgisftw: `04ab3875b15e4cbf10a413be7acfb1e5`, 18883 chars;
  - unfixed upstream body: `eb39c37c…`, 18206 chars;
  - `3c43bdd^:db/sql/FWA_WatershedAtMeasure.sql` body: `04ab3875…` (so "the body before #185 has the same md5" holds);
  - `3c43bdd` body: `eb39c37c…`. The only #185 hunk in that file is the 16-line removal.
- The local `fwapg` DB has md5 `04ab3875…` for both schemas.
- Scratch DB `fwapg_cr2_21121` (since dropped): postgis plus the search_path from `search_path.sh`, then the **patched** `schema.sql` with `ON_ERROR_STOP`.
  - The load returned rc 0, with both copies at `04ab3875…`.
  - `migrate.sh` applied 202610131450, the COMMENT is kept and the md5 is unchanged, so the migration is idempotent.
- The migration matches the `create_migration.sh` template (BEGIN/COMMIT) and the filename grammar.
- `hydrosheds.hybas_lev12_v1c`, `usgs.wbdhu12`, `hydrosheds.hydroshed`, `usgs.fwa_huc12` and `fwa_upstreambordercrossings` all exist in `schema.sql`, so the restored CTE resolves on a fresh install. The dependency on `usgs` being in search_path is not new: the lake path already has it.

**Draft claims**
- Line numbers at 8b3904e: `FROM exbc` is at 3929, and the whse function runs 3630–~4100 with its only `exbc AS` at 4051. Both correct. The postgisftw copy has `exbc AS` at 1454 and 1635, so it was not affected.
- `git ls-remote` shows upstream main is still 8b3904e. It has no `db/migrations/`, so "first file in db/migrations/" is true.
- #185 is "Xborder", merged as 3c43bdd. Both quoted phrases appear verbatim in its squash commit message ("do not load nhd or hydrosheds", "update fwa_watershedatmeasure to use new xborder data"). #184 is "discard hydrosheds/nhd data and related query logic", still open.
- Empty DB takes the lake branch: no row gives `NULL IS FALSE`, which is false, so it falls to `else`. Correct.
- Same result on a standard load: nothing upstream fills the hydrosheds or WBD tables (`git grep` is empty outside `schema.sql`). Locally both tables have 0 rows and the CTE yields nothing. Correct.
- CI re-apply: `schema.sql` has no `fwapg.db_version`, the service DB is ephemeral, and the migration is idempotent. Correct.
- pg_dump reproduces the hand-edit: prosrc is stored verbatim and the header is unchanged. Correct.
- Test points: located with ST_LocateAlong.
  - Bulkley is at 54.41N.
  - Kootenay at 160000 is 49.044N, -116.54, in BC just downstream of the Idaho border, with crossing USA_49.
  - Kootenay at 110000 is waterbody type L (Kootenay Lake).
  - Columbia at 1203700 is 49.18N, -117.71, between Castlegar and Trail.
  - The labels are accurate.
- Leaks: nothing private appears from **Title** down: no org name, local paths, hosts or private repos. The only references are upstream's own #184 and #185.

## Optional note (not a defect)

- `upstream_pr.md:21-26`: the psql transcript is introduced with "On a database loaded with `load.sh` from the current `schema.sql`". Per findings.md, the error was actually observed by calling an unfixed copy, created in a scratch schema, on a DB loaded before #185. That DB's whse_basemapping function is the working pre-#185 body, so the exact transcript was not run as shown.
  - The claim itself is true: it is a parse-time error, and the Bulkley point takes the non-lake branch on the same data.
  - The Testing section discloses the scratch-schema method.
  - If you want the wording to match the measurement exactly, change "On a database loaded…" to "e.g. on a database loaded…", or leave it as it is.
- Operator note, not posted text: `--head NewGraphEnvironment:fix-watershedatmeasure-exbc` is not on origin yet. Only an older `fix-exbc-nonlake` (4708405) is pushed, so `gh pr create` will fail until the branch is pushed. That older public branch carries an "accidentally removed" commit message. It is unrelated to this PR, but don't pick it by mistake.
