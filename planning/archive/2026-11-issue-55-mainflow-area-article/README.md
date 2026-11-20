## Outcome

A local article (`extras/mainflow_tree/article/`) puts seven cases of the main-flow tree's upstream-area rules (#4) on interactive maps, with a chart of the confluence share, tree against lookup. It renders from committed extracts with no database, and a `checks` chunk holds each case's key figures to the extracts and the README. Five cases look right on the ground. Case 3 found the rules' weak point. FWA draws polygon edges along streams, so a side-channel segment often lies on a polygon's boundary, and the midpoint test then decides by floating point: one side channel is the edge of two neighbouring floodplain polygons, and one went to the side channel, the other to the river. That went into #53 and `research/fwa_mainflow_tree.md`. Case 7, the README's "1 not explained", has a cause: local codes out of order on its line (#57). The imagery the maps need went into gq first (NewGraphEnvironment/gq#123, PR NewGraphEnvironment/gq#124), where review found World Imagery's grey placeholder tiles at zoom 19 over most of BC and at zoom 18 in the far north.

## Measurement

- "Moved up its line" (case 2): 15,848 polygons with valid codes plus the 19 bad-code polygons rule 1 also moves gives the README's 15,867 exactly.
- Case 3 (MORR): side channel 360226583 lies on the boundary of 7662562 for 3,409 m (midpoint inside by 4e-11 m, `pair_side`) and of 7662598 for 113 m (midpoint outside at 0 m, `lower`); 97% and 98% of them in the mapped ff04 floodplain; the third polygon 5%, 44 m from the side channel. In MORR 115 of 379 side-channel segments have their midpoint within 1 mm of a polygon edge.
- Case 7: the difference 1.632241 ha equals polygons 8628560 (0.214 ha) and 8632200 (1.418 ha), which the tree gives to 212038745.
- Case 6: 212039207's mouth is 351 m from the segment its area is carried to (the segments come within 42 m higher up: the first draft quoted 42 m, a closest approach, until review 1 caught it); the outlet 212039334 is on BC's edge at the Alaska border.
- Chart: 16,745 places; tree median 0.5%, 15,864 under a fifth; lookup median 50% at the 16,034 places with every lookup row (711 without).
- Extracts 2.3 MB. GDAL's default 3005 to 4326 transform moved case 5 (SHEK) by up to 0.34 m against the null shift used elsewhere; the explicit pipeline needs `+proj=axisswap` or the GeoJSON comes out lat/lon. Unordered float sums changed one row of `confluence_share.csv` between runs, now ordered.
- Wrong turns kept: "runs through" and "touches" for case 3 were a reading of the map until the checks measured that both polygons are bounded by the side channel.

## Owed

- After the gq PR merges and releases: name the gq version the article needs in `article/` and the README

Closed by: PR #58
