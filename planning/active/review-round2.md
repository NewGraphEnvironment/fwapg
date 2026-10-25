# Code-check round 2: indexpoint-tiebreak (staged diff in wt-upstream)

## Checklist read

- code-check-infra.md: read in full.
- code-check-python.md: read in full.
- code-check.md: read the prose of all 14 H3s under `## Mechanisms` (table rows skipped). Of the other H3s (Rules that stand alone, Security, Spreadsheets/PDFs), read only their index lines; none applies to this diff. Not read in full: 25 headings.
- code-check-spatial.md: read in full: "FWA `upstream_route_measure` misses the next segment's start", "FWA main flow is not edge type 1000 alone", "A Freshwater Atlas main stem's downstream end lies on the receiving river's centreline". The other ~138 headings (terra/sf/GDAL/etc.) were read from the index only.
- code-check-r.md: read in full: "Postgres row order is never fixed unless the query fixes it", "An `information_schema` lookup by the literal table name misses what Postgres resolves" (this includes the correlated-subquery name-resolution rule). The other ~166 headings were read from the index only.
- code-check-shell.md: read in full: "psql does not interpolate `:'var'` inside a dollar-quoted string, and `\quit N` exits 0". The other ~100 headings were read from the index only.

## Findings

- **[severity: bug]** db/migrations/202610240132__indexpoint_tiebreak.sql:73-80 (the measure change) together with `postgisftw.fwa_watershedhex` and `postgisftw.fwa_watershedstream` (db/schema.sql:1719-1721 and 1790-1792, which this diff does not touch). At a stream head the new measure falls outside these two functions' strict `s.upstream_route_measure > v_measure` filter. The migration's own "Stream head" comment (lines 32-38) describes this failure and fixes it only in FWA_LocateAlong. The accepted list covers only FWA_UpstreamTrace and FWA_DownstreamTrace, so these two web-service consumers of an FWA_IndexPoint measure are not covered by it.
  - **Measured on all 1,783,289 blue lines** (the top segment of each). The top segment's end m is below `upstream_route_measure` at only 84,860 (4.8%). So for about 95% of heads, the measure FWA_IndexPoint now returns there selects no segment. Under the old formula, `drm + length_metre < urm` held at 892,297 (50.0%).
  - **End to end**, for a point 20 m beyond the head of blue_line_key 356014037 (1002014.921672193, 1018388.1205244738, EPSG:3005):
    - Old FWA_IndexPoint gives measure 42.3489321277481. WatershedHex then returns 465 rows and WatershedStream 1.
    - New FWA_IndexPoint (migration applied, rolled back) gives 42.34953121357552. WatershedHex returns 0 rows and WatershedStream 0, while FWA_LocateAlong returns 1.
  - The new head test (blue_line_key 356067104) passes only because it sits in the 4.8%, where end m is 2e-14 below urm. At that point both functions still return rows.
  - **Remedy:** give both functions the "highest segment with drm <= measure" selection used in FWA_LocateAlong, or add them to the stated known-misses beside the traces.

- **[severity: fragile]** extras/channel_width/sql/fiss_stream_sample_sites_events.sql:34 and :87, via db/migrations/202610240132__indexpoint_tiebreak.sql:50-65 and :115. Every FISS site now goes through fwa_indexpoint.
  - **Mechanism:** fwa_indexpoint's `pt` CTE LEFT JOINs `fwa_watershed_groups_poly` on ST_Intersects. A point on the boundary between two groups therefore gives two `pt` rows, and `ORDER BY str.geom <-> (select geom from pt)` then raises `more than one row returned by a subquery used as an expression`. Each statement runs in one transaction, so one such site aborts the whole matching table.
  - **Reproduced** on the deployed (pre-migration) function and again under the migration, at a BULK boundary vertex, POINT(991702.864 1067015.186). The function's behaviour is pre-existing; what is new is that channel_width now depends on it (the old hand-rolled SQL did not error there).
  - **Does not fire today:** 0 of the 68,842 current sites (scratch41.fiss_stream_sample_sites_sp) intersect two groups. bcdata reloads the sites on every run, so it can fire on a later load.

## Not findings (checked)

- Tests: the harness gives 26 t, 0 not-t on the staged migration. Every mutant in scratchpad/mut reddens at least one case: a 7, b 3, c 1, d 2, e 1, f 2, g 20 (signature errors), h 1 (error).
- Round-1 fix verified. Every new case is a scalar subquery, an aggregate or EXISTS, so a zero-row call shows as blank or `f`. Correlated subqueries in the new tests are qualified (`i.`, `m.`, `p.`, `s.`). In the LocateAlong junction case the inner unqualified `geom` binds to fwa_stream_networks_sp, as intended.
- Each segment's first-vertex m equals its downstream_route_measure exactly (max difference 0 over 4,907,441 segments), so the tie-break's measure at a shared vertex is exactly the upper segment's drm. End m differs from urm by at most 7.3e-12.
- FWA_LocateAlong's `ORDER BY s.downstream_route_measure desc LIMIT 1` does not end on a unique key. Measured: there are 0 duplicate (blue_line_key, drm) pairs, raw or at 4 dp, so the pick is deterministic on current data.
- All 4,907,441 stream geometries are LineString (ZM), so ST_LineLocatePoint and ST_LineInterpolatePoint cannot meet a MultiLineString. No database object depends (pg_depend) on either function, so the DROPs succeed.
- Docs: the README, docs/01_usage.md and docs/03_functions.md examples changed by this diff reproduce exactly under the migration, measures and WKB included. Cosmetic only: docs/03_functions.md around line 886 (the FWA_UpstreamTrace example, which this diff does not touch) still shows 350.3003598130115, the old function's output; the new function returns 350.3003966398525.
- channel_width ran on 2,000 sites with the migration applied, in a rolled-back transaction: 1,898 events, one per site, all PointZM. The site-to-lut fan-out cannot change the output, because every row that survives `wscode_ltree_lookup = wscode_ltree` carries identical output columns.
- The cited issues resolve upstream: smnorris/fwapg#161 (z on the returned geom) and #86, which proposes these exact parameter names.
