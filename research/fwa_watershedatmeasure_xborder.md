# Cross-border area in FWA_WatershedAtMeasure

**Verified:** 2026-10-13 · **Issues:** NewGraphEnvironment/fwapg#1 (round 1 restored `exbc`, round 2 removed it), smnorris/fwapg#199 (round 1 upstream, superseded), smnorris/fwapg#200 (round 2 upstream), upstream issue 184 (drop hydrosheds/NHD) · **Produced by:** `fwa_watershedatmeasure()` run at four points on a loaded local fwapg, with migration runs on scratch DBs; SQL and results in `planning/archive/2026-10-issue-1-watershedatmeasure-exbc/` and `planning/archive/2026-10-issue-1-watershedatmeasure-drop-exbc/`

## Where the area outside BC comes from

Since upstream PR 185 ("Xborder"), `load.sh` inserts 2,053 cross-border watershed polygons (ids >= 1,000,000,000) into `whse_basemapping.fwa_watersheds_poly`. It does this through `load/fwa_watersheds_xborder_poly.sql`, which copies from a staging table that `load.sh` fills with ogr2ogr and then drops. `fwa_watershedatmeasure()` picks them up in its fundamental-watershed step (`prelim`) like any other polygon.

The function used to add the area through an `exbc` CTE, which read HydroBASINS (`hydrosheds.hybas_lev12_v1c`) and NHD WBD (`usgs.wbdhu12`). Since PR 185 those tables are empty, so `exbc` added nothing. Round 2 of #1 removed it from both copies (`db/migrations/202610131654__watershedatmeasure_drop_exbc.sql`, upstream smnorris/fwapg#200). The migration is the only place the fix lives: upstream merged it without the matching `schema.sql` edit, because `schema.sql` is a snapshot regenerated at a release. Until then, a db built from `schema.sql` has the broken copy (non-lake calls fail with `relation "exbc" does not exist`) until `db/migrate.sh` runs. The tables, schemas and `hydroshed()` / `fwa_huc12()` functions remain.

## A db is in one of three load eras, and a statement about "a db" must say which

| era | xborder polygons in `fwa_watersheds_poly` | hydrosheds / `usgs.wbdhu12` | xborder staging table |
|---|---|---|---|
| loaded before PR 185 | no | filled | never existed |
| loaded after PR 185 | yes | empty | dropped by the load |
| fresh `schema.sql`, not loaded | no | empty | exists, empty |

With `exbc` removed, a db from before PR 185 silently returns BC-only watersheds at points with area upstream across the border; it raises no error. The remedy is a rebuild, ending with `db/migrate.sh`. Running the xborder load file alone fails, because its staging table is missing, and re-running `load.sh` on an existing db fails at a `truncate`.

Code review of #1 found this mistake twice. Each time, a sentence about what a db contains was written from the one db that had been tested.

## Test points and expected results (loaded after PR 185)

| point | `(blue_line_key, measure)` | refine | area_ha | km² outside BC |
|---|---|---|---|---|
| Bulkley R. | (360873822, 166030) | CUT | 231944.70 | 0 |
| Kootenay R., 8 km below the Idaho border | (356570348, 160000) | CUT | 3469676.93 | 12452.9 |
| Kootenay Lake | (356570348, 110000) | LAKE | 4650676.78 | 12452.9 |
| Columbia R., between Castlegar and Trail | (356570372, 1203700) | CUT | 8743886.64 | 12452.9 |

The 12,452.9 km² is the 113 cross-border polygons under the Kootenay (`wscode_ltree <@ '300.625474'`). The function with and without `exbc` gives byte-identical geometries at all four points.

**Not measured:** where `fwa_watershed_groups_poly` has codes populated, a point downstream of a whole group would take the BC-only group polygon and exclude that group's cross-border fundamentals. A standard load writes the groups without codes, so this case is not reachable under the current `load.sh`.
