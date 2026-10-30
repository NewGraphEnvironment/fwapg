# Code-check round 1: indexpoint-tiebreak staged diff

Reviewed: `git -C <scratchpad>/wt-upstream diff --cached` (branch `indexpoint-tiebreak`), 2026-10-24.
Every changed file was read in full. Previous definitions were read from `db/schema.sql` and `HEAD:` (d955688).

## Checklist read

- code-check-infra.md: in full.
- code-check-python.md: in full (none of it applies, since the diff has no Python).
- code-check.md: the prose of all 14 H3s under `## Mechanisms`, with `|` rows and evidence blocks skipped. Of the rest, only the index was read: about 28 headings in Rules that stand alone, Security, and Spreadsheets and PDFs.
- code-check-r.md: read "Postgres row order is never fixed unless the query fixes it ...". Index only for the other 111 headings, which are R, DBI or testthat specific. That includes "sprintf %g", "information_schema lookup" and "::text spelling", which this diff does not touch.
- code-check-shell.md: read "psql does not interpolate `:'var'` inside a dollar-quoted string, and `\quit N` exits 0", which includes its note that bare-SELECT checks have no exit status. Index only for the other 67.
- code-check-spatial.md: read "FWA `upstream_route_measure` misses the next segment's start" and "A Freshwater Atlas main stem's downstream end lies on the receiving river's centreline". Index only for the other 92, including "FWA main flow is not edge type 1000 alone", which this diff does not touch.

## Findings

- **[severity: fragile]** tests/test_FWA_IndexPoint.sql:81-84 and tests/test_FWA_LocateAlong.sql:5-6. In each of these tests the function under test is in the FROM clause: a join for the stream-head round trip (`FROM postgisftw.FWA_IndexPoint(1298386.2, 743436.2, 3005) i, FWA_LocateAlong(...) l`), and `from fwa_locatealong(356360570, 14040.0058125527)` for the junction test. So when FWA_LocateAlong locates nothing, which is the defect each test exists to catch, the query returns **zero rows**. It prints no `f`, and the repo's verdict is a human checking that every row reads `t`. I measured this with labelled row counts through the harness:
  - With FWA_LocateAlong's upper bound restored, IndexPoint L81 returned 0 rows.
  - With the old `fraction * length_metre` measure restored (the exact HEAD formula), IndexPoint L81 returned 0 rows.
  - With `<` instead of `<=` in the LocateAlong pick, LocateAlong L5 returned 0 rows.

  The suite as a whole still went red under every mutation I tried, because sibling tests caught each one: LocateAlong L9, IndexPoint L55/L67, and IndexPoint L47/L74. Neither test fires on its own, though. Fix: wrap each in a scalar subquery, the same way the vertex test at L74 is written (`SELECT (SELECT ... ) as result`), or count rows (`count(*) = 1 AND bool_and(...)`). An empty result then prints a blank line or `f` instead of nothing.

No bugs, security issues or data-loss issues were found in the migration, the channel_width SQL or the docs.

## What was verified (evidence, not findings)

- The harness, with the staged migration and both test files: 26 `t`, 0 other.
- Mutation table, run through the harness against copies under `scratchpad/rev1/mut/`. Each mutation was checked against the line-labelled tests in `rev1/mtl/`:

  | mutation | red arms |
  |---|---|
  | LocateAlong upper bound restored | LocateAlong L9 `false`; IndexPoint L81 0 rows |
  | measure `fraction * length_metre` restored | IndexPoint L55, L67 `false`; L81 0 rows |
  | filters moved after the per-stream pick | IndexPoint L94 `NULL` |
  | `ST_ClosestPoint` wrapper removed | MultiPoint test L130 errors (`line_locate_point`) |
  | tie-break `drm ASC` | IndexPoint L34, L40 `false` |
  | filters deleted | IndexPoint L88, L94, L124 `false` |
  | `include_null_localcodes DEFAULT false` | IndexPoint L106 `false`. The "defaults" test does pin the declared defaults; it is not tautological. |
  | LocateAlong `<` instead of `<=` | IndexPoint L47 `false`, L74 `NULL`; LocateAlong L5 0 rows |

- Round trip: 10,741 IndexPoint rows (every 23rd FISS site, tolerance 500 m, up to 5 streams) were passed to FWA_LocateAlong. 0 returned no point, 0 were more than 1e-6 m off (max 5.8e-11), every row had `ST_M(geom) = downstream_route_measure`, and all were ZM.
- LocateAlong at segment starts and midpoints (4,933 sampled segments): 0 misses and 0 off at both. At `upstream_route_measure`, the old function missed 1,572 of 3,130 interior ends and all 1,803 heads. The new one misses 186 and 80. The 1,547 interior ends located a few mm off (max 3.8 mm, onto the next segment where measures overlap) are identical under old and new. So the change makes nothing worse.
- Data facts on the provincial table (4.9M segments):
  - `(blue_line_key, downstream_route_measure)` is unique, both raw and at 4 dp, so `ORDER BY drm DESC LIMIT 1` picks deterministically.
  - The geometry's start m equals `downstream_route_measure` (0 rows off by more than 0.05 mm).
  - The geometry's end m is within 7.3e-12 of `upstream_route_measure`.
  - The geometry is `LINESTRING ZM`, so `ST_LineInterpolatePoint` without `ST_LineMerge` is safe.
  - No row has a NULL `wscode_ltree`, so `include_disconnected => false` excludes only 999 streams.
- channel_width: I ran the HEAD and staged versions of `fiss_stream_sample_sites_events.sql` on every 20th site (3,438 sites, in temp tables, rolled back):
  - Old matched 3,156 sites and new matched 3,158. New is a superset (0 sites only in old, 2 only in new).
  - The blue_line_key differs for 0 common sites, and the measure differs by more than 1 cm for 0.
  - There are no duplicate sites and no NULL geometries.
  - The column types are unchanged (`distance_to_stream` double precision, `geom` geometry(PointZM,3005)).
  - WITH ORDINALITY stops the function being inlined, but the function's ORDER BY makes the ordinality order reliable.
- Docs: I re-ran the 03_functions examples 1 and 2 and the README query under the migration. They reproduce the new values and WKB exactly.
- No pg_depend dependents on either fwa_indexpoint, so the DROP without CASCADE is safe. FWA_LocateAlongInterval applies its own `(drm, urm]` filter, so it is unaffected.
- Issue citations: smnorris/fwapg#161 (add z to the indexpoint geom) and smnorris/fwapg#86 (where the maintainer proposes `include_disconnected` / `include_null_localcodes`) both resolve to the right upstream issues.

## Notes (not findings; each is accepted or out of scope)

- The new docs sentence "a measure at the top of the stream is located on its top segment" holds for IndexPoint's measure (the geometry's m). It does not hold for every `upstream_route_measure` column value. For 3.2% of segments the geometry's end m is about 1e-12 below the column, and ST_LocateAlong is called with the unrounded measure. So `FWA_LocateAlong(blkey, <top segment's upstream_route_measure>)` returned nothing for 80 of 1,803 sampled heads (4.4%). This falls inside the accepted 0.05 mm precision band, but the sentence reads as unconditional.
- The rewritten channel_width step took about 1.5x longer on the sample: 9.1 s + 4.3 s against 6.3 s + 2.3 s. The causes are the non-inlined call (WITH ORDINALITY), the per-call `bc_ind` intersect, and 100 candidate segments instead of 10. This is performance only.
- docs/01_usage.md lines 27-29 and 82-89 still show the old example outputs (350.2530543284006, 24.228). These lines were stale before this diff, but README.md and 03_functions now show the new value for the same query.
