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
- m1's database holds the tables (`fwapg.mainflow_tree_area*`, the tree). The md5 I computed (`c1e72f61…`) is not the memory's `0e553e9e…`, likely a different text form: Phase 3 checks the build against README numbers instead.
- gq installed 0.22.0, current 0.24.0. `gq_mapgl_layer(classes=)` is categorical only, so area is drawn in log classes computed in R. `gq_mapgl_basemap()` has `esri_topo_style()`, which is the pattern for an imagery option; no open gq issue covers imagery.
- Mapped floodplain (`stac_floodplains_bc`, ff04) covers BULK, KISP, MORR, NECR, KOTL and others, not KLUM/LSKE. `pair_side` polygons in covered groups: KOTL 34, MORR 17, NECR 14, BULK 5, FRAN 3, KISP 2, LCHL 1. So case 3 comes from one of these groups.
- The confluence share comes from `sql/qa.sql` (the `side`/`mouth` CTEs, 16,745 places).

## Decided at the gate (the owner, 2026-11-20)

- **Local only, nothing in docs.** Source, extracts and render script live in `extras/mainflow_tree/article/`. The rendered HTML is gitignored and viewed locally. This replaces the issue's "goes in the public docs", so #55's body is edited to match.
- **Extracts committed as text:** GeoJSON (EPSG:4326, 6 decimals, rows sorted on a unique key) and CSV, written by an extract script from the database. The render needs no database.
- **Imagery: add it to gq first.** File a gq issue and open a small gq PR adding an Esri World Imagery basemap option. The article uses it where judging the ground matters.

## Phase 1: Setup, gq imagery, issue body
- [ ] Upgrade gq 0.22.0 → 0.24.0 (`pak::pak("NewGraphEnvironment/gq")`), check `packageVersion`
- [ ] File a gq issue: an Esri World Imagery option for `gq_mapgl_basemap()` (keyless, attribution shown), from what #55 needs
- [ ] gq branch off its integration branch: `"esri_imagery"` in `gq_mapgl_basemap()` beside `esri_topo_style()` (World_Imagery MapServer tiles, Esri's credit), a test in `tests/testthat/test-gq_mapgl_basemap.R`, roxygen/NEWS per gq's conventions, `/code-check`, PR in gq (merge left to the owner)
- [ ] Install gq from that branch for the article's render
- [ ] Edit #55's body: Decisions (local only, extracts as text, imagery through gq, gq issue linked)
- [ ] `.gitignore`: `extras/mainflow_tree/article/*.html` (and the render's `*_files/` if any)

## Phase 2: Tests first, the article's checks
- [ ] `extras/mainflow_tree/article/mainflow_tree_area.Rmd` skeleton with a `checks` chunk that stops the render when an extract disagrees with the README:
  - case 1: 360216952 reads 53,007 ha below where 360884603 (51,420 ha) enters and 1,580 ha above; the lookup gives it 4.26–5.11 million ha
  - case 4: polygon 1000002557 is on the segment and line the README's rules give it
  - case 5: the segment's share equals its `mainflow_tree_area_shares` row and the polygon's `shared_ha` adds up
  - case 6: one step across a gap (`junction` or `line`) and one dead end that is an outlet
  - case 7: exactly one main-flow segment with `class IS NULL`, in TUTR
  - chart: 16,745 rows, 15,864 under 0.2, tree median about 0.005, lookup median about 0.5
- [ ] The checks fail before the extracts exist (run it and record the failure)

## Phase 3: Extracts
- [ ] Confirm the database holds the 2026-11-20 build: 1,898 share rows, Skeena 5,440,479 ha at its mouth, 360216952 at 53,007 ha
- [ ] `article/sql/<case>.sql`, one per case, each choosing its case deterministically (`ORDER BY` ending on a unique key) and its surroundings: tree segments (geometry from `fwa_stream_networks_sp`, `source`, `upstream_area_ha`, `local_area_ha`, `shared_area_ha`, `downstream_method`, the lookup's area from `fwa_streams_watersheds_lut` + `fwa_watersheds_upstream_area`), polygons (geometry, `method`, assigned segment, `area_ha`, `shared_ha`), share rows
  1. Skeena side channel 360216952 (LSKE) with tributary 360884603 and the Skeena reach they meet
  2. a `pair` polygon moved up its line through reaches with no polygon of their own (a readable one, chosen by rule)
  3. three `pair_side`-area polygons in a floodplain-covered group: one a side-channel segment runs through, one it only touches, one it does not touch
  4. Beaver River polygon 1000002557
  5. a length-share segment near the median share, and the polygon it came from
  6. a gap crossed (`junction`/`line`) and a dead end where the network ends
  7. the TUTR segment with `class IS NULL`
- [ ] Case 3 floodplain: the group's ff04 `floodplain` asset read with rstac from `images.a11s.one`, clipped to the case extent, written as GeoJSON
- [ ] Confluence CSV: `qa.sql`'s `side`/`mouth` CTEs plus the lookup's share at the same places, one row per place
- [ ] `article/article_extract.sh` (needs `DATABASE_URL`) runs it all with `ogr2ogr -f GeoJSON -t_srs EPSG:4326 -lco COORDINATE_PRECISION=6` into `article/extracts/`; report the total size
- [ ] Phase 2's checks pass on the extracts

## Phase 4: Maps and chart
- [ ] One map per case: `gq_mapgl_basemap()` (imagery for cases 1 and 3, positron otherwise unless imagery reads better), streams in log area classes through `gq_mapgl_layer(classes=)`, polygons filled by `method` with outlines, `gq_mapgl_popup()` for segment id, source, tree area, lookup area, share, method, `gq_mapgl_controls()`
- [ ] The chart: the confluence share, tree against lookup, over the 16,745 places (read the dataviz skill first; ggplot, log scale)
- [ ] `article/article_render.sh`: `rmarkdown::render()` to a self-contained `article/mainflow_tree_area.html`, run with `DATABASE_URL` unset

## Phase 5: Read the maps, write the verdicts
- [ ] Screenshot each map with chromote and look at it
- [ ] Per case in the article: what the map shows, whether the rule looks right on the ground, and what it leaves for #53
- [ ] `extras/mainflow_tree/README.md`: a short paragraph naming the article and its two commands
- [ ] #53's body: a pointer to the article and what the case-3 maps showed

## Owed at the end (reported, done after merge)
- [ ] After the gq PR merges and releases: name the gq version the article needs in `article/` and the README

## Validation
- [ ] Tests pass: the `checks` chunk; and with one extract number changed by hand, the render stops (restore the bug)
- [ ] Clean-checkout render: in a `git worktree` of the branch, `env -u DATABASE_URL -u PGSERVER ./article_render.sh` exits 0 and writes the HTML
- [ ] `/code-check` clean (once over the branch, `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

The rendered page is sent to the owner (SendUserFile) with the PR.
