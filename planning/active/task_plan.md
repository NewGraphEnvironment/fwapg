# Task: Article with interactive maps: does the main-flow tree's upstream area make sense on the ground? (#55)


#4 gave every tree segment an upstream area. Its polygon rules were first written from watershed codes and then corrected by geometry three times, each time from numbers (how many polygons sit on a segment that does not touch them), never from a picture. The choices that most need eyes:

- a polygon moves up its line only to a segment whose **midpoint** is inside it;
- a side channel takes a polygon only when one of its segments lies in it and no main flow of the polygon's own stream does (#53 asks whether this is really a floodplain question);
- a segment with no polygon at or above it takes a **length share** of the polygon it lies in;
- area is carried across 97 gaps and stops at 384 others.

## Context (from plan-mode exploration)

Explored:
- `docs/` is Sphinx + myst; `.github/workflows/build-docs.yml` publishes `docs/**` on any branch push. With the page kept local (gate), nothing goes under `docs/`, so no workflow runs.
- `.gitignore` ignores `data/`, `.*` and `*.gz` anywhere, so extracts go in `article/extracts/`, not `data/`.
- The local database holds the tables (`fwapg.mainflow_tree_area*`, the tree). The md5 I computed (`c1e72f61…`) is not the memory's `0e553e9e…`, likely a different text form: Phase 3 checks the build against README numbers instead.
- gq installed 0.22.0, current 0.24.0. `gq_mapgl_layer(classes=)` is categorical only, so area is drawn in log classes computed in R. `gq_mapgl_basemap()` has `esri_topo_style()`, which is the pattern for an imagery option; no open gq issue covered imagery (gq#123 filed for it).
- Mapped floodplain (`stac_floodplains_bc`, ff04) covers BULK, KISP, MORR, NECR, KOTL and others, not KLUM/LSKE. `pair_side` polygons in covered groups: KOTL 34, MORR 17, NECR 14, BULK 5, FRAN 3, KISP 2, LCHL 1. So case 3 comes from one of these groups.
- The confluence share comes from `sql/qa.sql` (the `side`/`mouth` CTEs, 16,745 places).

## Decided at the gate (the owner, 2026-11-20)

- **Local only, nothing in docs.** Source, extracts and render script live in `extras/mainflow_tree/article/`. The rendered HTML is gitignored and viewed locally. This replaces the issue's "goes in the public docs", so #55's body is edited to match.
- **Extracts committed as text:** GeoJSON (EPSG:4326, 6 decimals, rows sorted on a unique key) and CSV, written by an extract script from the database. The render needs no database.
- **Imagery: add it to gq first.** A gq issue (gq#123) and a small gq PR adding Esri World Imagery as `gq_mapgl_basemap(basemap = "esri_satellite")`. The article uses it where judging the ground matters.

## Phase 1: Setup, gq imagery, issue body
- [x] Upgrade gq 0.22.0 → 0.24.0 (`pak::pak("NewGraphEnvironment/gq")`, with the stale `GITHUB_PAT` unset), `packageVersion` reads 0.24.0
- [x] File a gq issue: NewGraphEnvironment/gq#123, Esri World Imagery as `"esri_satellite"` (the registry's id for the service)
- [ ] gq branch `123-imagery-basemap-esri-satellite` off gq's `main`: `"esri_satellite"` in `gq_mapgl_basemap()` through a shared `esri_raster_style()` beside `esri_topo_style()`, a test in `tests/testthat/test-gq_mapgl_basemap.R`, roxygen (NEWS is written by gq's release step), `/code-check`, PR in gq (merge left to the owner)
- [x] Install gq from that branch, pinned to its commit, for the article's render
- [x] Edit #55's body: Decisions (local only, extracts as text, imagery through gq#123), "What to build" and the gate questions removed
- [x] `.gitignore`: `extras/mainflow_tree/article/*.html` (and the render's `*_files/` if any)

## Phase 2: Tests first, the article's checks
Plan review (`review-plan.md`, findings 2, 5, 8, 10) changed this phase: checks are keyed on `linear_feature_id`, every case has a README number to check, and the red step is a stub extract.
- [x] Fix the extract files and columns first: `extracts/<case>_streams.geojson` (`linear_feature_id`, `blue_line_key`, `gnis_name`, `edge_type`, `tree` (bool), `source`, `upstream_area_ha`, `local_area_ha`, `shared_area_ha`, `downstream_id`, `downstream_method`, `lookup_area_ha`, `qa_kind`), `extracts/<case>_polygons.geojson` (`watershed_feature_id`, `watershed_group_code`, `wscode`, `localcode`, `method`, `linear_feature_id` (assigned), `assigned_blue_line_key`, `area_ha`, `shared_ha`, `kind`, `focus`, `moved`); streams also carry `focus`, `extracts/case5_shares.csv`, `extracts/case3_floodplain.geojson`, `extracts/confluence_share.csv` (`linear_feature_id`, `downstream_id`, `share_tree`, `share_lookup`, `lookup_missing`)
- [x] `extras/mainflow_tree/article/mainflow_tree_area.Rmd` skeleton with a `checks` chunk that stops the render when an extract disagrees with the README:
  - case 1: 123039830 reads 53,007 ha (just below the mouth of tributary 360884603, whose mouth segment 123039760 reads 51,420), 123039759 and 123039469 read 1,580, the bottom two (123041439, 123040995) 53,058; the lookup gives 360216952 5.06–5.11 million ha; 123043588, the side-channel mouth on main flow, carries a share of about 0.0104
  - case 2: the polygon's method is `pair` and its segment is above its own code's top reach (README: 15,867 moved, 3,547,842 ha)
  - case 3: one `pair_side` polygon with a side-channel midpoint inside it, one river-assigned polygon a side-channel segment touches with no midpoint inside, one on side-channel codes that no side-channel segment touches (README: `pair_side` 1,820 polygons, 95,860 ha)
  - case 4: polygon 1000002557 is `lower`, on blue line 359572098 (not 359024601), about 767,000 ha
  - case 5: the segment's share equals its `mainflow_tree_area_shares` row, and all share rows of its polygon sum to the polygon's `shared_ha` (README: 1,898 segments, median 14 ha)
  - case 6: one dead end carried across a gap (`mainflow_tree_qa.kind = 'dead_end'`, `downstream_method = 'junction'`; README 90) and one dead end that is an outlet (`downstream_method IS NULL`; README 383)
  - case 7: exactly one main-flow segment with `class IS NULL`: 212038783 in TUTR, tree 863.6 ha against lookup 865.3 ha
  - chart: 16,745 rows, 15,864 with `share_tree` under 0.2, `share_tree` median about 0.005, `share_lookup` median about 0.5, and the count with a missing lookup inflow reported
- [x] Red step: a stub extract with one wrong value makes the render stop; record the failure

## Phase 3: Extracts
- [x] Confirm the database holds the 2026-11-20 build: 1,898 share rows, the Skeena mouth segment at 5,440,479 ha, 123039830 at 53,007 ha
- [x] `article/sql/<case>.sql`, one per case (CTEs `seg_set` and `poly_set`), each returning the case's focus ids and its view; the script wraps each in one streams query (all network segments in the view, tree or not, with the lookup's area from the `qa_area.sql` join: `fwa_streams_watersheds_lut` + `fwa_watersheds_upstream_area`) and one polygons query. Written selection rules (review finding 7), every `ORDER BY` ending on a unique key:
  1. 360216952 and tributary 360884603 (LSKE), down through side channel 360216962 to main flow at 123043992 (review finding 3), and the inflows at that node
  2. a `pair` polygon whose segment's local code is above its own code's top reach, in LSKE or KLUM, crossing at least two polygon-less segments, area 50–500 ha, then by `watershed_feature_id`
  3. one floodplain-covered group (the first of MORR, NECR, BULK, KISP, KOTL holding all three kinds within 3 km of each other): a `pair_side` polygon a side-channel segment's midpoint is in; a river-assigned polygon a side-channel segment intersects with no midpoint inside; a polygon on side-channel-only codes that no side-channel segment intersects
  4. Beaver River polygon 1000002557 (BEAV) and the two Beaver main lines; the article says `lower` does not use the midpoint test (review finding 5)
  5. the share segment with the least `abs(share_ha - median share)`, then `linear_feature_id`, with all share rows of its polygon even outside the view
  6. built: the closest pair in one group of a dead end carried across (`junction`) and a dead-end outlet, then ids: TUTR 212039207 and 212039334 (segments within 77 m, mouths 166 m apart) (LTRE holds no dead-end outlet)
  7. 212038783 (TUTR) and its reach
- [x] Case 3 floodplain (built with `ogr2ogr` on the GeoPackage's `all_ff04` layer, EPSG:3005, clipped to the view; no R step needed): planned as an R step reading the group's `<wsg>_all_ff04` item with rstac from `images.a11s.one`, takes `floodplain.gpkg`, keeps `flood_factor` ff04, both `in_wsg` sides, clips to the case-3 view and writes sorted GeoJSON (review finding 11)
- [x] Confluence CSV: `qa.sql`'s `side`/`mouth` CTEs, plus the lookup's share over the same inflow set (the side channel's lookup area over the sum of the inflows' lookup areas), and `lookup_missing` where an inflow has no lookup row (review finding 4)
- [x] `article/article_extract.sh` (needs `DATABASE_URL`) runs the SQL through `ogr2ogr -f GeoJSON -t_srs EPSG:4326 -lco COORDINATE_PRECISION=6` and the floodplain step through Rscript, into `article/extracts/`. Cap 10 MB in all; no simplification of segments, which would move the midpoints being judged (review finding 12)
- [x] Phase 2's checks pass on the extracts

## Phase 4: Maps and chart
- [x] One map per case: `gq_mapgl_basemap()` (`"esri_satellite"` for cases 1 and 3, positron otherwise unless imagery reads better), streams in log area classes through `gq_mapgl_layer(classes=)` (segments dropped from the tree in grey), polygons filled by `method` with outlines, `gq_mapgl_popup()` for segment id, source, tree area, lookup area, share, method, `gq_mapgl_controls()`
- [x] The chart: the confluence share, tree against lookup, over the 16,745 places (read the dataviz skill first; ggplot, log scale)
- [x] `article/article_render.sh`: checks up front that the installed gq has `esri_satellite` and prints the pinned install if not (review finding 9), then `rmarkdown::render()` to a self-contained `article/mainflow_tree_area.html`, run with `DATABASE_URL` unset

## Phase 5: Read the maps, write the verdicts
- [x] Screenshot each map with chromote (SwiftShader flags for WebGL, screenshots to the scratchpad; review finding 13) and look at it
- [x] Per case in the article: what the map shows, whether the rule looks right on the ground, and what it leaves for #53
- [x] `extras/mainflow_tree/README.md`: a short paragraph naming the article and its two commands
- [x] #53's body: a pointer to the article and what the case-3 maps showed

## Owed at the end (reported, done after merge)
- [ ] After the gq PR merges and releases: name the gq version the article needs in `article/` and the README

## Validation
- [x] Tests pass: the `checks` chunk; and with one extract number changed by hand, the render stops (restore the bug)
- [x] Clean-checkout render: in a `git worktree` of the branch, `env -u DATABASE_URL -u PGSERVER ./article_render.sh` exits 0 and writes the HTML
- [ ] `/code-check` clean (once over the branch, `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

The rendered page is sent to the owner (SendUserFile) with the PR.
