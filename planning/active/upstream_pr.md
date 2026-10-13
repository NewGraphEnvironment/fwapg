# Upstream PR draft — NOT POSTED

To be posted only after the operator approves this text:

```
gh pr create -R smnorris/fwapg --base main \
  --head NewGraphEnvironment:fix-watershedatmeasure-exbc \
  --title "<title below>" --body-file <body below>
```

Before posting, decide on the `Claude-Session:` trailer in the two commit messages: keep it, or strip it with a reword and force-push of the fork branch.

---

**Title:** Restore exbc CTE in non-lake path of FWA_WatershedAtMeasure

**Body:**

The Xborder change (#185, 3c43bdd) removed the `exbc` CTE from the non-lake path of `whse_basemapping.fwa_watershedatmeasure` but kept the `FROM exbc` that reads it in `agg`. In `db/schema.sql` at 8b3904e, the non-lake path reads `FROM exbc` at line 3929, and the only `exbc AS` in that function is in the lake path (line 4051).

PL/pgSQL plans the whole `RETURN QUERY`, so **every** point the non-lake branch handles fails, not just points with area across the border. On a database loaded with `load.sh` from the current `schema.sql`:

```
=# SELECT area_ha FROM whse_basemapping.fwa_watershedatmeasure(360873822, 166030);  -- Bulkley River
ERROR:  relation "exbc" does not exist
```

The `postgisftw` copy of the function was not affected.

On an empty database (no data loaded) the lake check returns no row and the function takes the lake branch, so the error only shows once data is loaded.

### Change

- `db/migrations/202610131450__fix_watershedatmeasure_exbc.sql`: `CREATE OR REPLACE FUNCTION` with the CTE restored, unchanged from the version before #185. This is the first file in `db/migrations/`.
- `db/schema.sql`: the same 16 lines, so fresh installs get a working function.

After the change, the `whse_basemapping` function body is **byte-identical to the `postgisftw` copy already in `schema.sql`**: `md5(prosrc)` = `04ab3875b15e4cbf10a413be7acfb1e5` for both. The body before #185 has the same md5, so #185 changed nothing else in this function.

`db/README.md` says not to hand-edit `schema.sql`. I did it here because:
- the hunk is the one CTE;
- `pg_dump` emits a function body verbatim, so regenerating `schema.sql` after applying the migration should reproduce exactly these lines;
- without it, fresh installs stay broken until the next regeneration.

If you'd rather regenerate it yourself, drop the second commit.

### Testing

**Migration, as `test-migration.yml` runs it.** On a scratch database built from `schema.sql` at 8b3904e (postgis plus the `docker/db/search_path.sh` search_path), run from `db/`:
- `./migrate.sh --dry-run` lists the migration;
- `./migrate.sh` applies it;
- a second run reports "No pending migrations".

The function comment is kept. The edited `schema.sql` also loads cleanly with `ON_ERROR_STOP`.

**Behaviour, on a loaded database.** The fixed and unfixed bodies were created side by side in a scratch schema.

| call | refine_method | area_ha | km² outside BC |
|---|---|---|---|
| `(360873822, 166030)` Bulkley R. | CUT | 231944.70 | 0.0 |
| `(356570348, 160000)` Kootenay R., below the US border | CUT | 3469676.93 | 12452.9 |
| `(356570348, 110000)` Kootenay Lake (lake path, unchanged) | LAKE | 4650676.78 | 12452.9 |
| `(356570372, 1203700)` Columbia R., between Castlegar and Trail | CUT | 8743886.64 | 12452.9 |

The unfixed body raises `relation "exbc" does not exist` at the Bulkley point. "km² outside BC" is `ST_Area(ST_Difference(geom, ST_Union(fwa_bcboundary.geom))) / 1e6`.

### Notes

- **Cross-border area comes from `fwa_watersheds_xborder_poly`, not from this CTE.** `exbc` reads `hydrosheds.hybas_lev12_v1c` and `usgs.wbdhu12`, which `load.sh` no longer fills. That data reaches the result through `fwa_watersheds_poly`, so restoring the CTE fixes the error and adds no area.
- **The alternative is #184.** Dropping the `exbc` branches from `agg` in both paths, along the lines #184 proposes for the hydrosheds/NHD logic, gives the same areas. I went with the revert here as the smaller change to review. Happy to switch if you'd prefer that route.
- **The migration re-applies on every CI run.** The `fwapg-db:main` image has no `fwapg.db_version`, so `test-migration.yml` will apply this migration each time. It is idempotent.
