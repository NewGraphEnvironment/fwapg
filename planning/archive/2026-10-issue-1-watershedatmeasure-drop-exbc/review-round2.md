# Code-check round 2 (#1): review of the round-2 diff and the precondition comment

Reviewer: subagent, read-only. Diff: `33779a0..HEAD` on `1-watershedatmeasure-drop-exbc`.

## Findings

- **[fragile, low]** db/migrations/202610131654__watershedatmeasure_drop_exbc.sql:10-13 - the remedy "On a db loaded before #185, load them first" points at `load/fwa_watersheds_xborder_poly.sql`, but that file alone cannot be run on a pre-#185 db. It only does `INSERT ... SELECT FROM whse_basemapping.fwa_watersheds_xborder_poly` and then drops that table. On a pre-#185 schema the staging table does not exist: it is created only by #185's schema.sql (`git show 3c43bdd~1:db/sql/schema.sql` has 0 `xborder` matches, and no migration creates it), and it is filled by load.sh's ogr2ogr loop (`watersheds_xborder_poly` in the parquet table list, load.sh:26, from `fwa_watersheds_xborder_poly.parquet`). Someone following the comment literally gets `relation "whse_basemapping.fwa_watersheds_xborder_poly" does not exist`, which is loud, so no data is lost. The remedy just needs three steps: create the table (its DDL is in schema.sql), load it from the parquet, then run the file. Suggested wording: "...load them first: create `whse_basemapping.fwa_watersheds_xborder_poly` (see schema.sql), fill it from `fwa_watersheds_xborder_poly.parquet` as load.sh does, then run load/fwa_watersheds_xborder_poly.sql". Or simply "re-run load.sh". Everything else in the comment is accurate: the file name, that load.sh runs it (load.sh:150, added by #185 / 3c43bdd), the target table `whse_basemapping.fwa_watersheds_poly`, and the consequence (the old body unioned hydrosheds/NHD area, the new one reads only `fwa_watersheds_poly`, so without the xborder rows the area outside BC is silently dropped).

## Verified clean

- Folding the comment into the migration commit broke nothing. The comment is plain `--` lines between `BEGIN;` (line 1) and the first `CREATE OR REPLACE` (line 15). It is ASCII with no CR, contains no `$$` or `;`, and contains no psql `:var`. The file is still one `BEGIN; ... COMMIT;` with two `$$`-quoted bodies (lines 15-453 and 455-893, COMMIT at 895).
- Migration and schema.sql bodies are byte-identical (`cmp`): the migration's whse body equals schema.sql 3583-4020, its postgisftw body equals schema.sql 1199-1636, and the two copies equal each other. The comment lives only in the migration header, outside the bodies.
- The migration contains no `exbc` / `hydrosheds` / `wbdhu` outside the header comment.
- `git diff HEAD watershedatmeasure-drop-exbc -- db/` is empty, so db/ matches between the newgraph branch and the upstream branch. 6e9ed8e already contains the comment block.
- The upstream branch (`upstream/main..watershedatmeasure-drop-exbc`) touches only the migration and schema.sql. It has no `planning/`, no NGE issue numbers and no `Claude-Session:` trailer.
- migrate.sh: a db at version 202610131450 (round 1 applied) still picks up 202610131654 (string `>`). A fresh install bootstraps at '0' and re-applies it harmlessly (CREATE OR REPLACE).
- Planning files: no hosts, tailnet, credentials or private-repo links. findings.md names a local container (`fresh-db`) and DB name (`fwapg`) only.

## Verdict

No bugs or security issues. One low-severity accuracy fix to the new comment (above).
