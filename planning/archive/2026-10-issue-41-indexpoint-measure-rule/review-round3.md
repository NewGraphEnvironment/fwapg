# Code-check round 3: indexpoint-tiebreak (staged diff)

## Checklist read

- `code-check-infra.md` (38,115 bytes): in full.
- `code-check-python.md` (7,237 bytes): in full (nothing applies; the diff has no Python).
- All six `.index` files: in full.
- `code-check.md`: the prose of all 14 H3s under `## Mechanisms`, table rows skipped. Did not read the other 23 H3s (Rules that stand alone, Security, Spreadsheets/PDFs) beyond their index lines.
- `code-check-shell.md`: 1 heading read in full ("psql does not interpolate `:'var'`… `\quit N` exits 0"); 66 not read.
- `code-check-r.md`: 2 headings read in full ("Postgres row order is never fixed…", "An `information_schema` lookup by the literal table name…", which also carries the correlated-subquery rule); 109 not read.
- `code-check-spatial.md`: 3 headings read in full ("A Freshwater Atlas main stem's downstream end…", "FWA `upstream_route_measure` misses the next segment's start", "FWA main flow is not edge type 1000 alone"); 90 not read.

## The mechanism

Every function that takes `(blue_line_key, measure)` works out for itself which segment the measure is on, using its own hand-copied predicate. The copies differ: strict or closed at the top, rounded or not, `+ .01`, or no upper bound at all. Each then does its own arithmetic on that segment: `ST_LocateAlong` by m, a fraction `(meas - drm) / length_metre`, or `ST_LocateBetween`. All of them assume the measure falls in the range the producer used to emit, which was `[drm, drm + length_metre]`, fraction <= 1, strictly below `urm` at a head. Two lists agree by coincidence: the set of measures `FWA_IndexPoint` can return, and the set each consumer accepts. Nothing ties them together. So when the producer changed (m from the geometry, which reaches `urm` and can pass `drm + length_metre` by up to about 5 mm), every consumer whose copy encoded the old range broke separately: the nine strict-top functions in round 2, `FWA_UpstreamBorderCrossings`' fraction, and below, `FWA_SliceWatershedAtPoint`'s fraction.

The same assumption, that exactly one row matches, shows up in the other two instances. Exactly one segment per measure, enforced by an `ORDER BY ... LIMIT 1` at each site. Exactly one watershed group per point (round 1's #3), feeding a scalar context. The test-side version is round 1's #1: a call that matches nothing printed nothing, so an empty match read as a pass.

The fix stops at the callers the diff edited. `FWA_UpstreamBorderCrossings` got the fraction clamp. `FWA_SliceWatershedAtPoint` has the identical expression and is called by `FWA_WatershedAtMeasure`, but it was not touched (`code-check.md`, "A fix lands in one of two callers that share a harness").

## Enumeration: every function that takes blue_line_key + measure, or consumes FWA_IndexPoint output

| function (schemas) | how it selects / uses the measure | verdict against the new measure |
|---|---|---|
| FWA_IndexPoint (whse, postgisftw) | producer | changed; checked (see notes) |
| FWA_LocateAlong (both) | highest seg, `round(drm,4) <= m <= round(urm,4)`, `ST_LocateAlong` | changed; head and junction OK |
| FWA_UpstreamTrace (both) | same closed predicate; cut and `fwa_upstream` from the segment's drm | changed; head returns the upstream set from the top segment's start, no error |
| FWA_DownstreamTrace (both) | same closed predicate | changed; head OK (test) |
| FWA_NetworkTrace / NetworkTraceAgg (postgisftw) | delegate to `fwa_downstreamtrace` | covered by the trace change |
| FWA_WatershedHex / WatershedStream (both) | **unrounded** `drm <= m`, rounded closed top | changed; head OK. Lower end not rounded (note 2) |
| FWA_UpstreamBorderCrossings (whse) | `drm <= m + .01`, `urm > m` OR top segment; fraction clamped | changed; head clause untested (finding 2) |
| **FWA_SliceWatershedAtPoint (whse)** | `drm <= m ORDER BY drm DESC LIMIT 1`, no upper bound; `ST_LineInterpolatePoint(geom, ROUND((m - drm)/length_metre, 5))` | **not changed; errors on the new head measure (finding 1)** |
| FWA_WatershedAtMeasure (whse, postgisftw; also migration 202610131654) | `drm <= m ORDER BY drm DESC LIMIT 1` (accepts head), `ST_LocateAlong`; calls SliceWatershedAtPoint on CUT and BorderCrossings | own logic OK; inherits finding 1 on the CUT path |
| FWA_Upstream / FWA_Downstream measure predicates (whse, postgisftw.fwa_upstream) | point-to-point comparison with tolerance; no segment selection | unaffected |
| FWA_LocateAlongInterval / SegmentAlongInterval / SlopeAlongInterval | generated integer measures | accepted out of scope |
| extras/channel_width fiss_stream_sample_sites_events.sql | calls fwa_indexpoint (WITH ORDINALITY, so not inlined; order kept) | OK; `channel_width_measured.sql` join accepted out of scope |
| docs/01_usage.md, 03_functions.md, README | geom casts updated to `ST_Force2D` | OK |

Local DB: `pg_proc` lists no other function whose body mentions route measures or `indexpoint`, and nothing in `pg_depend` depends on the dropped `fwa_indexpoint` signatures.

## Findings

- **[severity: bug]** db/schema.sql:2904-2922 `whse_basemapping.fwa_slicewatershedatpoint`. The diff leaves it untouched, and it is reached through `FWA_WatershedAtMeasure` (both schemas) on the CUT path. It selects `drm <= meas ORDER BY drm DESC LIMIT 1` with no upper bound, then calls `ST_LineInterpolatePoint((ST_Dump(geom)).geom, ROUND((meas - drm) / length_metre, 5))`. At a stream's head, the measure `FWA_IndexPoint` now returns is the geometry's last m, which is `upstream_route_measure`. Where that runs past `drm + length_metre` by more than 5e-6 of the length, the fraction rounds above 1 and PostGIS raises `line_interpolate_point: 2nd arg isn't within [0,1]`. The old formula `drm + f * length_metre` capped the fraction at 1, so `FWA_IndexPoint` output could never get there. This is the same defect the migration clamps in `FWA_UpstreamBorderCrossings` (migration line 1087), in its sibling function.
  - Reproduced, migration applied in a rolled-back transaction: `FWA_IndexPoint(ST_EndPoint(geom))` of top segment 17091728 (blue line 360228283, edge 1450, waterbody type R) returns measure 1255.8763650310827 on that segment. `FWA_SliceWatershedAtPoint(360228283, 1255.8763650310827)` then raises the error, and so does `FWA_WatershedAtMeasure(360228283, 1255.8763650310827)` (CONTEXT: SQL function "fwa_slicewatershedatpoint"). Before the migration, the old IndexPoint measure (1255.875298293906) gave 0 rows from both, with no error. Same for heads 17079341 and 17060128.
  - Scope, measured province-wide: 87,104 of 1,783,289 blue-line heads have `round((urm - drm) / length_metre, 5) > 1`. 13,438 of those are on river (R) waterbodies, where WatershedAtMeasure picks CUT. Mid-stream measures do not trigger it: in BULK, LNIC and HORS, every segment whose end m passes `drm + length_metre` overlaps the next segment's start, so the slice picks the upper segment at a fraction near 0. All 596 cases there are heads.
  - Effect: one such point in a set-based call (`FROM pts, LATERAL FWA_WatershedAtMeasure(...)`) aborts the whole statement, where before it was one empty row.
  - Fix in the same migration: clamp as in BorderCrossings, `LEAST(GREATEST(..., 0), 1)`, or place the point with `ST_LocateAlong` by m.

- **[severity: fragile]** db/migrations/202610240132__indexpoint_tiebreak.sql:1096-1107 (BorderCrossings head clause) and tests/test_FWA_UpstreamBorderCrossings.sql:24. The new head clause (`OR (round(urm,4) >= round(meas,4) AND NOT EXISTS (higher segment))`) is a guard nothing tests. The only new test asserts `IS NULL`, and a head with no segment selected also returns NULL.
  - Mutation run: the head clause deleted and everything else kept, run with run_tests.sh: `t: 54  not t: 0`, the same as the unmutated tree.
  - The clause does change results. At the 598 side-channel heads in KOTL, SIML and OKAN (blue_line_key <> watershed_key, measure = end m), 163 return `USA_49` with the clause and NULL without it, for example blue line 356364911 at 1045.8644239278228 and 356365008 at 3416.2170150326283.
  - The existing clamp mutation (mut/k_bc_noclamp.sql) goes red only because the head clause selects the segment in the 359555315 case. So the clamp's guard also depends on this untested clause.
  - A test such as `FWA_UpstreamBorderCrossings(356364911, 1045.8644239278228) = 'USA_49'` would make the clause fail red when it is removed. Re-check that value against the final tree.

## Notes (checked, not findings)

1. **`FWA_IndexPoint` segment vs its measure inside an overlap band.** Where a segment's `urm` passes the next segment's `drm`, a point snapped onto the lower segment within that overlap returns the lower segment's `linear_feature_id`, wscode and localcode. Its m, however, is above the next segment's start. LocateAlong and the traces put that measure on the upper segment, and a localcode often changes at that junction. Example: 701772658 returned measure 68674.32452812427, where the next segment 701772792 starts at 68674.3244061854. In BULK, LNIC and HORS, 18,154 of 39,360 boundaries overlap (mean 0.4 mm, max 5.2 mm), 8,376 of them with a localcode change. Under the old formula the overlap was within 1 mm. This is the same "which side of the junction is decided by noise" class `research/fwa_position_codes.md` documents. A point falls in the band with probability of order band length / segment length (about 1e-6), so I left it out of the findings. It does mean the docs' "the segment ... its measure falls on" holds for the tie case only.
2. **Doc and header claim "both ends compared to 4 decimal places … select their starting segment the same way".** This is at docs/03_functions.md:304 and migration line 38. `FWA_WatershedHex` and `FWA_WatershedStream` (migration lines 814, 873, 938, 1018) keep an unrounded `drm <= v_measure`, so within 0.05 mm below a junction they pick the lower segment while LocateAlong picks the upper one. That is inside the accepted 4 dp band, so it is not a finding. Only the wording overstates it.
3. The `FROM`-form test cases, grants, filename, PointZM and 4 dp issues are the accepted tradeoffs and were not re-flagged. Baseline harness on the staged migration: `t: 54  not t: 0`.

Probe files: /private/tmp/claude-501/-Users-airvine-Projects-repo-fwapg/0995b622-5e08-4a5a-a71c-b83f9b831ab8/scratchpad/r3/ (slice2.sql, wam.sql, bchead.sql, mut_bc_nohead.sql). No worktree or repo file was edited.
