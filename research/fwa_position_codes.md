# Ordering positions on the FWA network

Source: measured 2026-10-07/08 on a full provincial fwapg (`fresh-db`, 4.5M segments in `fwa_stream_networks_sp`, 1.78M blue lines) while building `extras/pcic_crosswalk` (NewGraphEnvironment/fwapg#5; six code-check rounds, findings in `planning/archive/2026-10-issue-5-pcic-crosswalk/review-round*.md`). Junction sections revised 2026-10-11 (fwapg#14; `planning/archive/2026-10-issue-14-junction-vertex/`). Shared-vertex ties revised 2026-10-24 (fwapg#39; `planning/archive/2026-10-issue-39-indexpoint-tiebreak/`), then again the same day from the upstream review (fwapg#41, whose body carries the survey of point-to-stream picks; ad hoc SQL, rolled back).

## Local codes are not a coordinate system

`FWA_Upstream` decides "is b upstream of a" across blue lines by comparing `localcode_ltree` lexicographically. That holds only when every local code is exactly `wscode.position`, codes never decrease going up a blue line, and main and side channels are never compared by local code. None of the three holds province-wide:

- **Out of order along a blue line.** About 1% of segments on lines with PCIC outlets (13,177 of 928,409) have a local code below a segment downstream of them. Fraser example: drm 103,982 has `100.076435`, drm 107,577 has `100.076034`. On the upper Stikine one segment's `600.119863` (neighbours `600.6458…`/`600.6471…`) put 80 tributaries "above" a single point.
- **Outside the watershed code.** 569 segments have a local code not within their own watershed code; one at a river mouth (`600.757007` under `600.756349`) produced a 32-outlet cycle of "upstream" relations.
- **Nested more than one level** below the watershed code: 2,397 segments; the tributary arm then misplaces whole sub-basins.
- **Side-channel arm ignores the blue line.** `wscode_b = wscode_a AND localcode_b > localcode_a` fires for two points on the *same* blue line: 501 same-line pairs on 72 lines (Fraser, Stikine, Skeena) were judged the wrong way round.
- `downstream_route_measure` is only comparable within one blue line; ordering a side channel's measure against the main channel's assigned segments to the wrong outlet.

Patching inputs (repairing out-of-order codes) reproduced the defect one axis over: repairs copied bad codes from neighbours that were themselves out of order.

## What works: blue-line downstream paths

Give every blue line its parent line and the measure where it joins, and compare positions by walking that chain (`extras/blue_line_paths/sql/blue_line_paths.sql`, moved there from the PCIC job in fwapg#2; about 35 min province-wide measured 2026-10-09, not the 4-6 min first recorded; max 17 lines on a path, mean 4.18, from `fwapg.blk_paths` the same day). Junction sources, in order, and what each fixed:

1. **Code equality** (main stems): lowest segment of the parent-code main stem whose `localcode = tributary wscode` (the same join `load/fwa_stream_networks_order_parent.sql` uses). An equality is immune to ordering defects; within 10 m of the traced junction on all but ~100 of 1.5M lines. Deferred when the mouth touches a side channel of the parent: the water enters where the side channel rejoins (Birkenhead on the Lillooet: 2 km and 18 m3/s apart).
2. **Touch** (≤ 1 m from the mouth) to a lower code or a side channel's own main stem.
3. **Rounds**: touch a line that already has a parent. Braids rejoin through sibling braids: without this 17,200 side channels (Kitsumkalum into the Skeena) had no path.
4. **Side channel fallback** to its own main stem (local-code equality, else nearest within 1 km): a Seton side channel ends 619 m from the Seton and cut off Cayoosh Creek.
5. Otherwise **no path**. An unbounded projection of the mouth onto the parent put the Okanagan (mouth 110 km from the Columbia), Kettle and Similkameen — which reach the Columbia in the US — on the Columbia in BC (+162 m3/s).

Acyclic by construction: every edge goes to the same code or lower; main stems always leave their code; same-code edges only from side channels, to their main stem or to a line attached in an earlier round.

Data facts the construction relies on (measured): no blue line has two watershed codes or two watershed_keys; no side channel's watershed_key line is itself a side channel; one watershed code has two main lines (Beaver River 359572098 / 359024601); FWA lines are digitized from the downstream end (M = 0); 0 multipart segments.

## `fwa_indexpoint()` keeps one segment per stream, then you filter

It returns the nearest segment per blue line and can exclude only edge type 6010. Filtering its output afterwards drops the whole stream when that nearest segment is unusable. On 38,729 PCIC outlets (150 m, 5 streams): 651 streams lost that had a usable segment in reach; causes were segments with no `fwa_streams_watersheds_lut` row (7,157 candidates; 6,822 have no local code), `999.*` codes (634) and edge 1425 (8). Running the same search with the filters before the per-stream pick avoids it (`pcic_crosswalk02_candidates.sql`). See also fresh `research/fwa_point_snap.md`.

## A point on a shared vertex is equally near two segments

*Measured 2026-10-10, fwapg#13.* About 1% of PCIC outlets (449 of 48,716) sit exactly on the vertex two segments of one blue line share, so "the nearest segment" is a tie, and an `ORDER BY ST_Distance` with no second key lets the plan choose. Two builds on two machines agreed on all but 2 only because their spatial indexes were built alike; a lowest-id tie-break moved 449. FWA measures run `[downstream_route_measure, upstream_route_measure)`, so the rule that follows the data is the segment *starting* at the vertex (`downstream_route_measure DESC`), the one above a tributary junction.

*Revised 2026-10-24, fwapg#39.* The point does not have to sit on the vertex: any point whose nearest point on both segments is the vertex ties, which is every point in the wedge outside a bend. Old against new `fwa_indexpoint()` (5 streams) changed segment on 9 of 242 random BC points and 57 of 1,000 points near segment ends. All were exact float ties, half had differing local codes, and the stream set never changed. That is a floor, since it misses ties the old plan happened to resolve upward. `fwa_indexpoint()` itself had no second key until fwapg#39 (migration `202610240132__indexpoint_tiebreak.sql`, now `downstream_route_measure DESC, linear_feature_id`). Its old answer moved with the plan: with index scans off, 08EC013's gauge went from 5086970 to 5086038. When the lower segment won, the measure it returned (`downstream_route_measure + length_metre`) could fall short of the next segment's start, and `FWA_LocateAlong` returned no point (08KD006, 14040.005812552621 against 14040.0058125527). bcfishobs (`sql/process.sql:157-163`) and bcfishpass PSCIS snapping carry the same untied pick in their own SQL. 7,198 of 307,121 bcfishobs observations (2.34%) sit on such a tie, and 3,464 (1.13%) at a tie where the local codes differ. fresh's `frs_point_snap()` breaks ties on lowest id (fresh#266).

*Revised again 2026-10-24, fwapg#41 (from the review of smnorris/fwapg#201).* At the old 08KD006 measure `FWA_WatershedAtMeasure` returns no polygon either; at the upper segment's start it returns 2,861 km² (WSC 2,863). smnorris/bcbasins delineates gauge watersheds through `fwa_indexpoint` then `fwa_watershedatmeasure` on blue line and measure, and reads an empty watershed as needing DEM refinement, so a gauge on this tie takes that path. No other nearest-stream pick breaks the tie: not `extras/channel_width/sql/fiss_stream_sample_sites_events.sql` here, the eight in bcfishobs `sql/process.sql`, or PSCIS, falls and dams in bcfishpass (smnorris default branches, 2026-10-24); only `pcic_crosswalk02_candidates.sql` does. The measure is computed two ways: bcfishpass and bcfishobs read the geometry's M (`ST_InterpolatePoint`), `fwa_indexpoint` takes `downstream_route_measure + fraction * length_metre`. On 08KD006's lower segment they give 14040.004934962686 and 14040.005812552621, and both fall below the upper segment's start, 14040.0058125527. `fwa_indexpoint` builds its point with `ST_ClosestPoint`, which drops the line's z and m (smnorris/fwapg#161).

## Which side of a junction: water joining at a segment's start does not pass it

*Measured 2026-10-11, fwapg#14.* The same convention decides where a tributary's water goes. Its junction measure is the start of the main-stem segment above it, so the water passes the segment *below* and not that one. A test of "joins at or above the segment's start" (`>=`, as `fwapg.blk_on_or_upstream` does for points) put the step one segment too high at 2,373 of 18,942 junctions whose tributary carries over 1 m3/s in June; a strict test leaves 678, which come from other causes (an outlet higher on that segment whose PCIC flow includes the tributary, and the area lookup below). The same strictness applies to which outlet a tributary drains to (the outlet's segment must start below the junction), and an outlet on the vertex whose PCIC descendant joins there belongs on the segment below (6 outlets). Where nothing above a junction carries flow of its own (a stub, a connector, a side channel), the segment above it carries none: 135 segments, one a 1 ha construction line that had carried 734 m3/s.

## Measures that name the same point disagree, by field

*Measured 2026-10-11, fwapg#14 code-check rounds 2-3.* Two measures computed differently for one point do not compare exactly, and an exact `<=` or `>=` between them decides the side of a junction by noise:
- A segment's `upstream_route_measure` misses the next segment's `downstream_route_measure` by 1 mm to 1 cm at about 137k boundaries (by up to 9.3 mm). `downstream_route_measure + length_metre` agrees with it (over 1 mm at only 52, at most 3 mm). Take a segment's top from the next segment's start, not from `upstream_route_measure`.
- Measures interpolated along a segment (`downstream_route_measure + ST_LineLocatePoint(...) * length_metre`: snapped points, touch junctions in `extras/blue_line_paths`) differ from the segment start they name by float noise: 1,529,850 of 1,570,499 first-step junctions in `fwapg.blk_paths` sit exactly on a segment start, 1,569,124 within 1 mm. Code junctions are always exact; touch junctions are exact at only 41,098 of 71,331.
- The noise is enough to matter: outlets 1e-14 to 1e-10 m above a junction on the segment below it were skipped by its tributary, leaving one of 2,130 ha (blue line 356567538) with no flow in any month, and 1,052 segments with none.

Compare measures from different sources within 1 mm. Segment starts on one blue line come from one table and compare exactly. No FWA segment with a fundamental watershed is shorter than 1 cm, so a 1 mm band never spans a segment.

## Not fixed: area lookup at tributary mouths

`fwa_streams_watersheds_lut` can give a tributary-mouth segment the fundamental watershed of the stream it joins, so upstream area there is the parent's. In the PCIC build, 2,184 of 36,380 sub-basins got no local area of their own (8% of local runoff appears only at their outlet).
