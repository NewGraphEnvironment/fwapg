# Code review, round 1: branch 1-watershedatmeasure-drop-exbc

Reviewed: diff 33779a0..aafc47a (db/migrations, db/schema.sql), plus the upstream-side
branch `watershedatmeasure-drop-exbc`. Read-only; probes ran on copies in the scratchpad.

## Verdict

No bugs in the SQL. One fragile precondition worth one sentence in the PR, not a code change.

## Findings

- **[fragile]** db/migrations/202610131654__watershedatmeasure_drop_exbc.sql:1-8 — the
  migration assumes the database already holds the xborder polygons in
  `whse_basemapping.fwa_watersheds_poly` (inserted by `load/fwa_watersheds_xborder_poly.sql`
  since upstream 3c43bdd, Xborder #185). This is the first migration upstream ever ships,
  so `migrate.sh` will bootstrap version `0` and apply it to any database built from any
  earlier `schema.sql`, including one loaded before #185. On such a database the old
  function worked (hydrosheds/usgs were populated and `exbc` was defined in both paths),
  and after this migration cross-border watersheds (USA_49, AB_120, YTNWT_60 upstream
  crossings) silently come back BC-only, with no error. For databases loaded after #185
  the change is purely a fix. Remedy if wanted: one line in the migration comment / PR
  body saying a pre-#185 database needs `load/fwa_watersheds_xborder_poly.sql` (or a
  reload) before this migration; a code guard is not warranted given the maintainer asked
  for this shape.

## Checked and found correct

- CTE/comma structure at all four edited sites: river path `cut AS (...),` runs straight
  into `agg as (`; the `to_agg` subquery ends at `FROM method m` then `) as to_agg,`; lake
  path `prelim` now closes with `)` (no trailing comma) before the final `SELECT`; the lake
  `w` subquery's last arm is `SELECT p.geom FROM prelim p` then `) w`. No orphan `UNION ALL`.
- Migration bodies vs schema.sql bodies: extracted each function from `CREATE ...` to
  `$$;` and diffed after the header line. postgisftw migration == schema, whse_basemapping
  migration == schema, and the two schema copies == each other (only difference anywhere
  is `CREATE` vs `CREATE OR REPLACE` and the schema name).
- schema.sql vs upstream/main: only exbc CTEs and their `UNION ALL ... FROM exbc` arms are
  removed (5 hunks: upstream's whse_basemapping copy had already lost the river-path CTE,
  which is the original bug). No other lines touched.
- No `exbc` left in schema.sql; the only hits in db/ are the migration's own comment.
- The revert leaves nothing dangling: no file references `202610131450` or
  `fix_watershedatmeasure_exbc` outside planning/.
- Deleting the already-merged 202610131450 migration does not break `migrate.sh`: it
  only selects files whose prefix is `>` the latest `db_version.tag` and keeps no
  checksums or file list, so a DB at 202610131450 picks up 202610131654 (string-greater),
  and a DB that never applied 1450 goes straight to 1654, which is a full
  `CREATE OR REPLACE` of both functions and needs nothing from 1450. (db/README.md says
  "do not delete applied migration files"; here the deleted file's effect is wholly
  superseded, so nothing is lost for bringing old DBs forward.)
- schema.sql records no `db_version`, so a fresh install then `migrate.sh` re-applies
  1654; it is idempotent (identical bodies), so harmless.
- Upstream-side branch: `db/migrations` and `db/schema.sql` are byte-identical to this
  branch; it touches only those two files, and its commit messages carry no planning/,
  NGE issue numbers or `Claude-Session:` trailer. When newgraph later merges upstream/main
  with this PR merged as-is, the identical file at the identical path will not conflict.
- No hosts, credentials or private links in the changed db/ files.
