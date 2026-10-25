# Findings — fwa_indexpoint(): one tie rule and measure method (#41)

## Issue context

## Problem

smnorris/fwapg#201 (the tie-break from #39) was reviewed on 2026-10-24. Simon asked for two things before the migration lands:

1. Compare its tie-break with the other queries that match points to streams, so they all break the tie the same way. Possibly by using `fwa_indexpoint()` everywhere.
2. Fold in the enhancements in smnorris/fwapg#86 (options for which streams are returned) and smnorris/fwapg#161 (the returned point has no z).

#39 is done and archived. This issue is the revision that grows out of the review, and it lands on the same upstream branch (`indexpoint-tiebreak`), so smnorris/fwapg#201 carries one migration rather than two.

## What is known (measured 2026-10-24, on a loaded provincial fwapg)

**No other point-to-stream pick breaks the tie.** Every nearest-stream `DISTINCT ON` / `LIMIT 1` pick on smnorris/fwapg `main` (ae8f7c7), smnorris/bcfishpass `main` (620dbe4) and smnorris/bcfishobs `master` (217b650), excluding migration archives:

| query | orders by | tie-break |
|---|---|---|
| fwapg `fwa_indexpoint` (before smnorris/fwapg#201) | `distance_to_stream` | none |
| fwapg `extras/channel_width/sql/fiss_stream_sample_sites_events.sql:102` | `distance_to_stream` | none |
| bcfishobs `sql/process.sql:163` and 7 more picks in the file | `distance_to_stream` | none |
| bcfishpass `model/01_access/sql/load_falls.sql:74`, `load_dams.sql:74` | `str.geom <-> pt.geom limit 1` on one blue line | none |
| bcfishpass `model/01_access/pscis/sql/02_pscis_streams_150m.sql:74` | `distance_to_stream` | none |
| bcfishpass `model/01_access/pscis/sql/04_pscis.sql:208`, `05_pscis_points_duplicates.sql:80` | name score, then weighted distance | none on distance |

Only this fork's `extras/pcic_crosswalk/sql/pcic_crosswalk02_candidates.sql` breaks it, on the upper segment, as smnorris/fwapg#201 does.

**The measure is computed two ways.** bcfishpass and bcfishobs take it from the geometry's M (`ST_InterpolatePoint`). `fwa_indexpoint` takes `downstream_route_measure + ST_LineLocatePoint(...) * length_metre`. At a segment end they differ. At 08KD006 (Willow River above Hay Creek, blue line 356360570):

| segment | method | measure |
|---|---|---|
| 703862843 (lower) | geometry M | 14040.004934962686 |
| 703862843 (lower) | `fwa_indexpoint` formula | 14040.005812552621 |
| 703862887 (upper) | either | 14040.0058125527 (its start) |

Both lower-segment measures fall below the upper segment's start, between the two segments' recorded ranges, so `FWA_LocateAlong` and `FWA_WatershedAtMeasure` find nothing there. One consistent rule is a tie-break **and** a measure method.

**smnorris/fwapg#161.** The returned point is `ST_ClosestPoint(stream_geom, pt_geom)`, which drops the line's z and m. `ST_LineInterpolatePoint(stream_geom, <fraction>)` keeps both, and its m is the geometry-M measure bcfishpass uses.

**smnorris/fwapg#86.** Filtering `fwa_indexpoint` output afterwards drops a whole stream when its nearest segment is unusable: on 38,729 PCIC outlets (150 m, 5 streams), 651 streams with a usable segment in reach were lost (`research/fwa_position_codes.md`, "`fwa_indexpoint()` keeps one segment per stream, then you filter"). Filters applied before the per-stream pick avoid it, which is what smnorris/fwapg#86's `include_disconnected` (`999` codes) and `include_null_localcodes` would be. smnorris/fwapg#86's `match_type = flow` is harder: Simon's own comment there shows a double-line river (the Cowichan) that a same-watershed rule would exclude. A better `bc_ind` and a marine/terrestrial flag are also listed there.

New parameters change the signature, so the migration drops and recreates `whse_basemapping.fwa_indexpoint` and `postgisftw.fwa_indexpoint`. Defaults that keep today's behaviour keep existing callers working.

## Decisions for the plan gate

The recommended option for each was proposed to Simon on smnorris/fwapg#201 on 2026-10-24 (https://github.com/smnorris/fwapg/pull/201#issuecomment-6390955988). He replied the same day (https://github.com/smnorris/fwapg/pull/201#issuecomment-6391033612): he expected the tie to be handled in his other queries, since he has debugged it before, and will take a closer look in November. He has not agreed to or turned down any of the three options, so they are still open at the plan gate.

1. **smnorris/fwapg#86 scope:** both filter options, with defaults that keep today's behaviour (recommended); or those plus `match_type = flow`; or nothing from smnorris/fwapg#86.
2. **Measure method:** geometry M via `ST_LineInterpolatePoint`, which matches bcfishpass and bcfishobs and closes smnorris/fwapg#161 in the same change (recommended); or keep the formula and add z separately.
3. **Consistency outside fwapg:** document the rule in fwapg and draft, not post, notes for bcfishobs and bcfishpass (recommended); or move their picks onto `fwa_indexpoint`, which is a larger change in those repos.

## Scope

- One migration on `indexpoint-tiebreak`, replacing `202610240132__indexpoint_tiebreak.sql` rather than adding a second, plus tests. smnorris/fwapg#201 is updated in place.
- `extras/channel_width/sql/fiss_stream_sample_sites_events.sql` is in this repo upstream and in scope for the same rule.
- #40 (the newgraph cherry-pick of smnorris/fwapg#201) is held until upstream settles, then re-cherry-picked. The local fwapg is not migrated until then.

Relates to #39, smnorris/fwapg#201, smnorris/fwapg#86, smnorris/fwapg#161.



## Plan-mode exploration (2026-10-24, read-only probes on the loaded provincial fwapg)


- **`ST_LineMerge` drops M** on this PostGIS 3.5.2 / GEOS 3.9.0 (`ST_NDims` 4 → 3). The column is already `geometry(LineStringZM, 3005)`, so the merge does nothing useful, and it is the reason the current function cannot return M.
- `ST_M(ST_LineInterpolatePoint(geom, f))` agrees with bcfishpass's `ST_InterpolatePoint` to within 2.3e-10 over 74,274 sampled points.
- `upstream_route_measure` is generated as `downstream_route_measure + ST_Length(geom)`, and it equals the end M. `length_metre` is the source attribute, so the formula `drm + f * length_metre` can run past `upstream_route_measure` into the ~mm gap before the next segment. `FWA_LocateAlong` places a measure by M (`ST_LocateAlong`) and filters segments on `[drm, urm)` rounded to 4 dp. The formula's measure and its point therefore disagree, and near a segment top `FWA_LocateAlong` finds nothing.
- At 08KD006 both lower-segment measures return 0 rows from `FWA_LocateAlong` (14040.0049 is above the lower segment's `urm` after rounding). Only the tie-break fixes that vertex. The measure method fixes interior and near-top points.
- `fiss_stream_sample_sites_events.sql` computes the measure by formula, then places the point by M. It already filters `localcode IS NOT NULL AND NOT wscode <@ '999'` before its pick, which is exactly #86's two options set to false.
- Only `postgisftw.fwa_indexpoint` calls the function inside fwapg. Its body is a SQL string, so no dependency blocks a DROP.

- PostGIS 3.5.2, GEOS 3.9.0, PostgreSQL 17.5 on the local fresh-db.
- `fwa_locatealong(356360570, 14040.004934962686)` and `(…, 14040.005812552621)` both return 0 rows. Lower segment 703862843: drm 13543.8751554134, urm = end M = 14040.004934962686. Upper 703862887: drm = start M = 14040.0058125527.

## Baseline on rebuilt point sets (Phase 1, 2026-10-25 UTC)

Scratch schema `scratch41` on the local fresh-db (dropped at the end): `pts` (242 `random`, one per watershed group via `ST_GeneratePoints(..., 41)`; 1,000 `ends`, segment starts offset up to 30 m; 1,000 `tops`, on the line at fraction 1 - 1e-7 of a segment over 10 m), and `res` (`fwa_indexpoint(pt, 5000, 5)` from the installed pre-#39 function `orig`, the d955688 body and the new body). SQL in the session scratchpad, not committed.

- **Formula against geometry M:** at most 3.0 mm apart (median 0.02 mm on `ends`, 0.13 mm on `random`), over 1 mm on 54 of 5,000 / 33 of 1,190 / 135 of 5,000 rows; never over 1 cm. `length_metre - ST_Length(geom)` reaches 4.2 mm.
- **New against d955688 with default flags:** identical blue line, segment and rounded distance on every row of all three sets. The returned point is within 2.3e-10 m of `ST_ClosestPoint`, XYZM on every row, and `ST_M(geom)` equals the measure.
- **`FWA_LocateAlong` misses** (d955688 → new): `ends` 251 → 488, `random` 171 → 311, `tops` 1,207 → 1,335. Every d955688 miss on `random` and `ends` is a snap to a stream's head (fraction 1 on the blue line's top segment). The new misses that d955688 did not have are the same class: there the new measure equals `upstream_route_measure` exactly, and `round(upstream_route_measure, 4) > measure` rejects it. The formula passed about half of these by luck, where `length_metre` < `ST_Length`. For the nearest stream only: `random` 25 → 42. The rest of `tops` is `FWA_LocateAlong`'s 4 dp rounding where a segment's `upstream_route_measure` overlaps the next one's start (149060446 ends at 4416.172501, 149060347 starts at 4416.172069).
- **`FWA_WatershedAtMeasure`'s point step** (highest `downstream_route_measure <= m`, then `ST_LocateAlong`), d955688 → new: `ends` 230 → 0, `random` 156 → 0 (21 → 0 for the nearest stream), `tops` 929 → 0. The formula overshoots the segment's M range and no point exists; geometry M cannot.
- So the measure change fixes `FWA_WatershedAtMeasure` outright and unmasks `FWA_LocateAlong`'s exclusion of a stream's head, which went to the user (decision 5).
- **Start and end M:** `ST_M(ST_StartPoint(geom)) = downstream_route_measure` on all 4,907,441 segments. The end M differs from `upstream_route_measure` on 306,883 (156,253 below, 149,630 above).

## Verification of the final migration (Phase 6, 2026-10-25 04:30-04:50 UTC)

All runs on the local fresh-db. The tests ran inside one transaction that rolled back (harness `run_tests.sh` in the session scratchpad strips the migration's own BEGIN/COMMIT, refusing if more than one of each is present or any other transaction control remains, and runs with `ON_ERROR_ROLLBACK`). The comparisons used scratch copies of the functions in `scratch41`, so no installed function changed.

**Tests:** 26 of 26 `t` (21 in `test_FWA_IndexPoint.sql`, 5 in `test_FWA_LocateAlong.sql`). Each premise is shown to be load-bearing by reverting it alone:

| revert | not `t` | cases that catch it |
|---|---|---|
| `ST_LineMerge` back | 6 | ZM/SRID, closest point, geometry-M measure, both round trips, MultiPoint |
| formula measure | 2 | geometry-M measure (2 mm off), 08KD006 round trip |
| filters after the pick | 1 | null-localcode stream comes back empty |
| `FWA_LocateAlong` upper bound back | 1 | stream head |
| tie-break removed | 1 | 08KD006 segment |
| wrapper drops the flags | 2 | Teanook excluded; null-localcode case |
| no `ST_ClosestPoint` before `ST_LineLocatePoint` | 1 | MultiPoint input |
| d955688 as a whole | 19 | errors on 5/7-argument calls plus the above |

**Point sets, new against d955688 (default flags, 5 streams):** identical blue line, segment and rounded distance on all 11,190 rows; measure moves by at most 3.0 mm; point within 2.3e-10 m of `ST_ClosestPoint`; every point ZM with m = measure.

**`FWA_LocateAlong` old rule against new rule**, over every measure in `res` plus 7,218 sampled segment starts, ends and midpoints: never loses a point the old rule found and never moves one. With the new measure, found rises from 9,050 to 11,148 of 11,182; segment-end M values from 749 to 2,332 of 2,405. All 107 remaining misses are one class: the 4 dp rounding picks the next segment where this segment's end overlaps the next one's start by under 0.05 mm (precision, left alone).

**`FWA_WatershedAtMeasure`'s point step:** misses 230 → 0 (`ends`), 156 → 0 (`random`), 929 → 0 (`tops`).

**Filters, PCIC outlets (48,716; 150 m; 5 streams):** `false, false` returns 92,606 rows, identical to an independent query (all segments within 150 m passing both filters, nearest per stream, top 5): 0 rows differ either way. Filtering the default output afterwards keeps 91,879, so the filters before the pick recover 727 streams. (Not comparable to the research file's 651, which also counted segments missing from `fwa_streams_watersheds_lut` and edge 1425.) No segment has a NULL `wscode_ltree`; 328,961 have no local code and 208,189 are `999`.

**Timing:** 1,000 `ends` points × 5 streams: d955688 2.2-2.4 s, new 1.9 s, new with both filters 2.0-2.1 s.

**channel_width, FISS sites (68,842 MultiPoints, loaded with `bcdata bc2pg` into `scratch41`):** old 63,413 sites matched in 37 s, new 63,501 in 105 s (each site now searches a 100-segment window and repeats the watershed-group lookup). One row per site in both.
- 60,499 same segment, measure and point moved by up to 4.6 mm: the old point came from `ST_LocateAlong` at the formula measure, so it was off the snap by the formula error.
- 2,837 identical; 63 segment differs on the same stream (vertex ties).
- 88 sites only in the new table, all rows the old code dropped because `ST_LocateAlong` at the formula measure was empty: 79 directly, 9 through a vertex tie that the old pass 2 gave to the lower segment.
- 14 blue line differs: 8 from the window (the old 10 nearest *segments* filled with one or two streams; the new search finds a nearer stream with a matching code, e.g. site 1046 115 m → 52 m; 3 of them move from pass 2 to pass 1) and 6 exact ties between two streams.
- 0 sites only in the old table.
- Consumer `channel_width_measured.sql` joins events to segments on `(downstream, upstream]`, the opposite convention: 439 old and 450 new events match no segment (a vertex measure now sits exactly on the upper segment's start). Pre-existing, as is its leftover filter `e.localcode_ltree = '400.536025.503903.677855'`, which limits it to one stream. Reported for Simon, not changed.

**Same upper-bound filter elsewhere:** `FWA_UpstreamTrace` and `FWA_DownstreamTrace` (both schemas) also require `round(upstream_route_measure, 4) > measure`, so they reject a stream-head start the same way. Out of scope (decision 5 covers `FWA_LocateAlong`); noted for Simon.

**Docs:** the example outputs in `docs/03_functions.md` and `README.md` were already stale against today's load (installed function: Sooke 350.300360 m against the documented 350.253054); regenerated from the new function (350.300397).

## Code-check round 2 and decision 6 (2026-10-25 05:06-15:20 UTC)

Round 2 (`review-round2.md`) found two real defects; both reproduced before acting.

- **The geometry-M measure breaks every function with a strict upper bound at a stream's head, not just `FWA_LocateAlong`.** Of 1,783,289 blue lines, the top segment's end m equals `upstream_route_measure` at 1,616,885 (90.7%), is below it at 84,860 and above it (by at most 7.3e-12) at 81,544; the old formula fell below it at 892,297 (50.0%). So `round(upstream_route_measure, 4) > m` or `upstream_route_measure > m` rejected about 95% of new head measures against about 50% of old ones. Nine more functions carry the bound: `FWA_UpstreamTrace`, `FWA_DownstreamTrace`, `FWA_WatershedHex`, `FWA_WatershedStream` (both schemas), `FWA_UpstreamBorderCrossings` (whse). `FWA_LocateAlongInterval` and `FWA_SegmentAlongInterval` bound generated interval measures, not caller measures, and are left alone. The user chose the same rule in all nine (decision 6).
- **A point on a watershed-group boundary fails `fwa_indexpoint`** (installed and new): the `pt` CTE joined the groups, so an exact BABL/BULK vertex gave two rows and `ORDER BY str.geom <-> (select geom from pt)` raised "more than one row returned by a subquery". The reviewer's printed coordinate was rounded and fell inside one group; the exact vertex (991961.3809999991, 1065362.4670000002) reproduces it. Fixed with an `EXISTS`; regression case first.

**`FWA_UpstreamBorderCrossings`** is the exception to the uniform edit. It takes segments with `downstream_route_measure <= meas + .01`, so within 1 cm below a junction it takes both segments, and the upstream set includes the tributary joining there; reducing that to one segment would have dropped it. It keeps its selection and also accepts the top segment at the head. Its slice fraction `(meas - drm) / length_metre` exceeds 1 for a measure from m near a segment top, and the deployed function errors there (`line_interpolate_point: 2nd arg isn't within [0,1]`, 1 of 258 interior measures); clamped to [0, 1].

**First version, no upper bound at all, was wrong for the traces.** The whse `FWA_DownstreamTrace` reads `whse_basemapping.fwa_streams`, which stops short of some network segments (blue line 360221829 ends at 92.75 there and runs to 185.13 in `fwa_stream_networks_sp`). At 142.13 the old filter returned nothing; "highest segment at or below" took the top `fwa_streams` segment and returned a 1,835-row trace starting 49 m downstream of the point, silently. `FWA_LocateAlong` and `FWA_WatershedHex` cannot do this (their `ST_LocateAlong` comes back empty), but the traces can. Every selection now also requires `round(upstream_route_measure, 4) >= round(m, 4)`: closed at the top, so the head is in and a measure past its segment is out. At 4 dp, because an exact `>=` would reject the 4.6% of heads whose end m sits 1e-12 above `upstream_route_measure`.

**First comparison (no-upper-bound bodies, 400 interior measures, 1,138 heads):** nothing lost and nothing changed where both versions returned rows. Gains: downstream trace at 988 heads, watershed stream at all 1,138, upstream trace at 12, border crossings `NULL` → `USA_49` at 4 heads (streams cut at the border, whose head sits on it); interior gains were 36 head snaps (3 of them one ulp below `upstream_route_measure`) and the 2 `fwa_streams` gap cases above. The first attempt ran out of memory after 11.5 min (`string_agg` of whole traces with geometry over 1 GB); per-row hashing fixed it.

**Tests after round 2:** 54 of 54 across five files (`test_FWA_IndexPoint`, `_LocateAlong`, `_UpstreamBorderCrossings`, `_DownstreamTrace`, `_UpstreamTrace`). New: boundary point, head through `FWA_WatershedStream`, `FWA_WatershedHex` and `FWA_LocateAlong` (blue line 356014037, end m = `upstream_route_measure`), border crossings at a head where the fraction exceeds 1, downstream trace at a head and one metre past it. Thirteen one-change reverts, each red: a 10, b 3, c 1, d 3, e 1, f 2, g (d955688) 24, h 1, i (group join) 1, j (watershed upper bound) 2, k (no clamp) 2, l (trace upper bound) 1, m (no closed top) 2.

**Final comparison (closed-top bodies, 15:19-15:35 UTC; 258 interior measures, 300 heads, the 2 `fwa_streams` gap cases):** no losses and no changed result wherever old and new both return rows, in any of the four functions compared. The gap cases are empty again, as with the old filter. Heads: watershed stream gained at all 300, downstream trace at 224 (the other 76 are streams missing from `fwa_streams`), upstream trace at 3. Interior: 36 trace and 38 watershed-stream gains, all head snaps (the extra 2 are heads on streams missing from `fwa_streams`); border crossings lost its one error. `FWA_LocateAlong` new: 1 row at the 356067104 head, 0 one metre past it.

## Code-check round 3 and the enumeration that ended the review (2026-10-25 15:36-16:00 UTC)

Round 3 (`review-round3.md`), asked for the mechanism: every function taking (blue line, measure) decides for itself which segment a measure falls on and does its own arithmetic on it, each assuming the measures the old producer emitted (fraction at most 1, strictly below `upstream_route_measure` at a head). Nothing ties the producer's range to the consumers'. It found:
- **`FWA_SliceWatershedAtPoint`** (called by `FWA_WatershedAtMeasure` on rivers) slices at `ROUND((meas - drm) / length_metre, 5)`, which rounds above 1 at 87,104 of 1,783,289 heads (13,438 on rivers). It errored at the head of blue line 360228283 (1255.8763650310827), and the deployed version errors just below it too (1255.876). Clamped to [0, 1]; regression case first.
- **The border-crossings head clause had no test** (removing it left 54/54; the case asserted `IS NULL`, which no selection also satisfies). Added `FWA_UpstreamBorderCrossings(356364911, 1045.8644239278228) = 'USA_49'`, a side-channel head whose upstream crosses into the US.
- Wording: the watershed functions compare the segment start unrounded; docs and migration comment corrected.

**Enumeration (mechanical, over `pg_proc.prosrc` of the deployed database).** Consumers whose source has a strict upper bound on `upstream_route_measure` or divides by `length_metre`: 16. The migration covers 12: `FWA_LocateAlong`, `FWA_UpstreamTrace`, `FWA_DownstreamTrace`, `FWA_WatershedHex`, `FWA_WatershedStream` (both schemas each), `FWA_UpstreamBorderCrossings` and `FWA_SliceWatershedAtPoint`. The other 4 are `FWA_LocateAlongInterval` and `FWA_SegmentAlongInterval` (both schemas), whose bounds apply to integer interval measures they generate. Producers of a measure with the `length_metre` formula: 1, the old `fwa_indexpoint`, replaced. Nothing left above its source.

**Tests:** 56 of 56 across five files. Fifteen one-change reverts, each red: a 10, b 3, c 1, d 3, e 1, f 2, g (d955688) 27, h 1, i 1, j 2, k 2, l 1, m 2, n (border head clause) 1, o (slice clamp) 2.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `count(*)` over the new function on a MultiPoint returned 1, read as "MultiPoint works" (review B1 marked refuted) | Wrong probe: the function is inlined and output columns the query does not read are never computed. FISS MultiPoints then raised `line_locate_point: 2nd arg isn't a point`. Test now selects measure and geom; fixed with `ST_ClosestPoint` before `ST_LineLocatePoint` |
| Filter test pinned the default's `linear_feature_id` (44074756) from unrounded coordinates; the 0.1 m-rounded point picks 44074764 | Pin the property (default segment has no local code), not the id |
| Appended LocateAlong cases fused with the existing last statement | The existing test had no closing `;` and no final newline; added the `;` |
| Harness refused the migration: the bare `BEGIN` opening each plpgsql body matched its guard | Guard on statement-level `BEGIN;`/`COMMIT;`/`ROLLBACK;` only |
| Comparison of the nine functions: out of memory after 11.5 min | `string_agg` of whole trace rows (with geometry) passed 1 GB; aggregate per-row md5s |
| Revert builder stopped at `d_locate_urm` and left d-h as stale files from the previous migration, which then ran | Anchor text differed in `FWA_LocateAlong` (comment above the SELECT). Those results discarded; builder rerun with every anchor asserted, and the files listed before running |
| `sed -i 's/…/' file` failed: "undefined label" | This machine's `sed` is BSD; `-i` takes the next argument as the suffix. Used python |
