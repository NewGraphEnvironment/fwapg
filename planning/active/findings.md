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

## Errors Encountered

| Error | Resolution |
|-------|------------|
