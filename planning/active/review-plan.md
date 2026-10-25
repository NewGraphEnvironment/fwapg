# Plan review (#41), Plan agent, 2026-10-24

Spawned 03:41Z, delivered 04:30Z. The agent returned its findings as reply text (Plan type, no Write); summarised here with the verdict after a probe.

| id | claim | verdict |
|---|---|---|
| B1 | `ST_LineLocatePoint(geom, pt)` errors on MultiPoint input (FISS loads as multi) | **Refuted** on PostGIS 3.5.2: the scratch new body returns 1 row for `ST_Multi(point)`. A MultiPoint test is added so an older PostGIS shows it |
| B2 | Migration and channel_width SQL carry their own BEGIN/COMMIT, so an outer ROLLBACK harness commits; channel_width hardcodes `fwapg.` | **Accepted**: the harness strips both and rewrites the schema, checked by grep (Phase 6) |
| G1 | DROP + CREATE resets grants; pg_featureserv caches function metadata | **Accepted**: PR note and an Owed item |
| G2 | Wrapper's unqualified `FWA_IndexPoint` resolves against the migrating role's search_path at CREATE | **Accepted**: qualify it |
| G3 | channel_width's geom column type comes from the cast; keep the column set | **Accepted** |
| G4 | channel_width difference classes, `channel_width_measured.sql`'s `(drm, urm]` join, debug filter at `channel_width_measured.sql:42` | **Accepted** into Phase 6; the debug filter is pre-existing, noted for Simon |
| G5 | Rounded distance in the site `DISTINCT ON` | **Accepted**: order by `WITH ORDINALITY` |
| G6 | `docs/01_usage.md:185` casts to `geometry(Point, 3005)` and will break; stale doc outputs | **Accepted** |
| A1 | Start M may differ from `downstream_route_measure`, putting a vertex measure on the lower segment | **Refuted**: 0 of 4,907,441 segments differ at the start. The end M differs from `upstream_route_measure` on 306,883 (156,253 below, 149,630 above) |
| A2 | Filters in the KNN WHERE make the window the 100 nearest *passing* segments; NULL wscode drops under `include_disconnected => false` | **Accepted** for the docs wording; NULL wscode count to check |
| A3 | A database that applied d955688 will not re-run the same timestamp | **Accepted**: PR note |
| A4 | pg_featureserv and boolean parameters | Open: check against pg_featureserv's docs; raise with Simon if unclear |
| A5 | Double watershed-group lookup per site in channel_width | **Accepted**: report in the timing |
| AC1-AC5 | Tautological M test; filter tests must prove before-the-pick; PCIC target must be an independent count; "new = 0 misses" too strong; tests are read by eye | **Accepted**: Phase 3 and 6 rewritten |
| O1, O2 | Keep the old function alongside (scratch schema already does); regenerate doc outputs after Phase 6 | **Accepted** (O1 already the harness) |
| S1, S2 | pcic_crosswalk and fresh's `frs_point_snap()` still use the formula; no bcfishpass/bcfishobs caller blocks the DROP | **Accepted**: Owed issues |
