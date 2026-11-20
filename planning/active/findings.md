# Findings — Article with interactive maps: does the main-flow tree's upstream area make sense on the ground? (#55)

## Issue context

**If we do it:** we can look at the main-flow tree's upstream area on a map, case by case, and judge whether its rules make sense on the ground: above all the midpoint test that decides whether land beside a river belongs to the river or to a side channel. **If we never do:** every rule in #4 stays judged by counts alone. Nobody has looked at a map of even one case.

## Problem

#4 gave every tree segment an upstream area. Its polygon rules were first written from watershed codes and then corrected by geometry three times, each time from numbers (how many polygons sit on a segment that does not touch them), never from a picture. The choices that most need eyes:

- a polygon moves up its line only to a segment whose **midpoint** is inside it;
- a side channel takes a polygon only when one of its segments lies in it and no main flow of the polygon's own stream does (#53 asks whether this is really a floodplain question);
- a segment with no polygon at or above it takes a **length share** of the polygon it lies in;
- area is carried across 97 gaps and stops at 384 others.

## What to build

A short article with interactive maps, in this repo's docs, built by us to view (it does not have to be linked from the docs index).

Cases, one map each, streams coloured by area and the polygons drawn, with popups for the numbers:

1. A Skeena test side channel (360216952, 360222216 or 360237491): the lookup's area beside the tree's, and the tributary that enters it.
2. A polygon that moved up its line through reaches with no polygon of their own.
3. Side-channel land, three kinds: a polygon a side-channel segment runs through, one it only touches, one it does not touch. Mapped floodplain overlaid where it exists (#53).
4. The Beaver River cross-border polygon (1000002557), which a codes-only rule moved to the wrong line.
5. A stream with no polygon of its own: the length share it was given and the polygon it came from.
6. A dead end where area is carried across a gap, and one where the network ends.
7. The one main-flow segment that differs from the lookup with no explanation (TUTR).

Plus one chart: the share of the confluence a side channel takes where it meets main flow, tree against lookup, over all 16,745 places.

## Decisions (the owner, 2026-11-20)

- It goes in the public docs of this repo. Publishing is not a concern either way.
- Interactive maps with gq's MapLibre GL helpers (`gq_mapgl_*`, with the mapgl package). No QGIS.
- Planned here, built later.

## Found while looking (2026-11-20), to verify at the plan

- The docs are Sphinx with `myst_parser` (`docs/conf.py`, `docs/index.rst`, Markdown pages). `.github/workflows/build-docs.yml` runs on **any push that touches `docs/**`, on any branch**, and pushes the built site to `gh-pages`. So a file under `docs/` is published by the next push; a page that should only be built locally needs to live elsewhere or be excluded in `conf.py`.
- An R-rendered page with map widgets is standalone HTML, which Sphinx does not build. Likely shapes: render it with rmarkdown to a self-contained file and ship it through `html_extra_path` (or `_static`), with the `.Rmd` and a build script beside it; or keep it out of the Sphinx build entirely. A choice for the plan gate.
- gq is at 0.24.0; the copy first looked at was 0.22.0. Its `gq_mapgl_basemap`, `gq_mapgl_layer`, `gq_mapgl_network`, `gq_mapgl_popup`, `gq_mapgl_classes`, `gq_mapgl_controls` and `gq_mapgl_style` are the pieces, and its `gq-mapgl-composition` vignette is the pattern to read first.
- Mapped floodplain for case 3: the `stac_floodplains_bc` catalogue holds what is mapped so far, and the `floodplains` package can map more where a case needs it.
- PR #54 is merged (2026-11-20), so this starts from `newgraph`.
- The data comes from a database with the tree built (`extras/mainflow_tree/mainflow_tree.sh`): `whse_basemapping.fwa_stream_networks_mainflow_tree`, `fwapg.mainflow_tree_area`, `fwapg.mainflow_tree_area_polygons`, `fwapg.mainflow_tree_area_shares`, `fwapg.mainflow_tree_area_qa`, with `fwa_stream_networks_sp` and `fwa_watersheds_poly` for geometry and the lookup for the comparison. The article should read small extracts saved with it, so it renders without a database.

## Questions for the plan gate

- Where the source and the rendered page live, given the workflow publishes `docs/` on push.
- Whether the extracts (a few hundred features per case) are committed beside the article or fetched.
- Which basemap: gq's, and whether imagery is needed to judge the floodplain cases.

## Done when

- The article renders from a clean checkout with one command and no database.
- Each of the seven cases has a map that shows the segments, the polygons and the areas involved, with the numbers the README quotes for it.
- It says, per case, whether the rule looks right on the ground, and what it leaves for #53.

## Not in scope

Changing #4's rules (that follows from what the maps show, in #53 or a new issue). Mapping new floodplain.

Follows #4 (built in PR #54). Related: #53 (side channels and floodplain), #2 (the main-flow tree).



## Case selection (2026-11-20, the local database, the 2026-11 build)

- "Moved up its line" (case 2): method `pair`, local code under its watershed code, given to a segment of another local code: 15,848 polygons, 3,545,764 ha. With the 19 bad-code polygons the README says rule 1 also moves, 15,867 and 3,547,842 ha, the README's figures exactly. Pick: 7745172 (LSKE, 363 ha, 3 segments crossed).
- Case 3 (`sql/case3_search.sql`, about 70 s): MORR 7662562 (a side-channel midpoint in it), 7662598 (a side channel touches it, no midpoint in it), 9742603 (no side channel touches it, 44 m from one), all adjacent. Side channel 360226583 is the edge of the first two (3,409 m and 113 m on their boundaries); the midpoint test splits them by 4e-11 m.
- Case 5: 180011290 (SHEK), share 13.695 ha against a median of 13.692; polygon 8442664 gives shares to 8 segments.
- Case 6: LTRE has two dead ends carried across and no dead-end outlet; the closest junction/outlet pair is in TUTR, 212039207 and 212039334, whose segments come within 77 m (mouths 166 m apart; 212039207's mouth is 351 m from 212039249, where its area is carried).
- Case 1: 360216952's water reaches main flow through side channel 360216962 at 123043992; the side-channel mouth is 123043588.
- Extracts: 2.2 MB in all. Floodplain for MORR: `https://stac-floodplains-bc.s3.us-west-2.amazonaws.com/morr_all_ff04/floodplain.gpkg`, layer `all_ff04`, EPSG:3005.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `pak` 401 "Bad GitHub credentials" | The shell carries a stale `GITHUB_PAT`; `env -u GITHUB_PAT -u GITHUB_TOKEN -u GH_TOKEN Rscript --vanilla -e 'pak::pak(...)'` |
| ogr2ogr "source layer has no coordinate system" on a PG `-sql` result | `-s_srs EPSG:3005` |
| GDAL warned "several coordinate operations" (case 5, SHEK); `-ct_opt ONLY_BEST=YES` then failed outside the best operation's area of use | An explicit null-shift `-ct` pipeline; it needs `+proj=axisswap +order=2,1` at the end, or the GeoJSON comes out lat/lon. Cases 1-4, 6, 7 byte-identical to GDAL's default; case 5 moved at most 0.34 m |
