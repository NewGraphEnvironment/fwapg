# Ordering positions on the FWA network

Source: measured 2026-10-07/08 on a full provincial fwapg (`fresh-db`, 4.5M segments in `fwa_stream_networks_sp`, 1.78M blue lines) while building `extras/pcic_crosswalk` (NewGraphEnvironment/fwapg#5; six code-check rounds, findings in `planning/archive/2026-10-issue-5-pcic-crosswalk/review-round*.md`).

## Local codes are not a coordinate system

`FWA_Upstream` decides "is b upstream of a" across blue lines by comparing `localcode_ltree` lexicographically. That holds only when every local code is exactly `wscode.position`, codes never decrease going up a blue line, and main and side channels are never compared by local code. None of the three holds province-wide:

- **Out of order along a blue line.** About 1% of segments on lines with PCIC outlets (13,177 of 928,409) have a local code below a segment downstream of them. Fraser example: drm 103,982 has `100.076435`, drm 107,577 has `100.076034`. On the upper Stikine one segment's `600.119863` (neighbours `600.6458…`/`600.6471…`) put 80 tributaries "above" a single point.
- **Outside the watershed code.** 569 segments have a local code not within their own watershed code; one at a river mouth (`600.757007` under `600.756349`) produced a 32-outlet cycle of "upstream" relations.
- **Nested more than one level** below the watershed code: 2,397 segments; the tributary arm then misplaces whole sub-basins.
- **Side-channel arm ignores the blue line.** `wscode_b = wscode_a AND localcode_b > localcode_a` fires for two points on the *same* blue line: 501 same-line pairs on 72 lines (Fraser, Stikine, Skeena) were judged the wrong way round.
- `downstream_route_measure` is only comparable within one blue line; ordering a side channel's measure against the main channel's assigned segments to the wrong outlet.

Patching inputs (repairing out-of-order codes) reproduced the defect one axis over: repairs copied bad codes from neighbours that were themselves out of order.

## What works: blue-line downstream paths

Give every blue line its parent line and the measure where it joins, and compare positions by walking that chain (`extras/pcic_crosswalk/sql/pcic_crosswalk01_paths.sql`; 4-6 min province-wide, max 16 hops, mean 3.9). Junction sources, in order, and what each fixed:

1. **Code equality** (main stems): lowest segment of the parent-code main stem whose `localcode = tributary wscode` (the same join `load/fwa_stream_networks_order_parent.sql` uses). An equality is immune to ordering defects; within 10 m of the traced junction on all but ~100 of 1.5M lines. Deferred when the mouth touches a side channel of the parent: the water enters where the side channel rejoins (Birkenhead on the Lillooet: 2 km and 18 m3/s apart).
2. **Touch** (≤ 1 m from the mouth) to a lower code or a side channel's own main stem.
3. **Rounds**: touch a line that already has a parent. Braids rejoin through sibling braids: without this 17,200 side channels (Kitsumkalum into the Skeena) had no path.
4. **Side channel fallback** to its own main stem (local-code equality, else nearest within 1 km): a Seton side channel ends 619 m from the Seton and cut off Cayoosh Creek.
5. Otherwise **no path**. An unbounded projection of the mouth onto the parent put the Okanagan (mouth 110 km from the Columbia), Kettle and Similkameen — which reach the Columbia in the US — on the Columbia in BC (+162 m3/s).

Acyclic by construction: every edge goes to the same code or lower; main stems always leave their code; same-code edges only from side channels, to their main stem or to a line attached in an earlier round.

Data facts the construction relies on (measured): no blue line has two watershed codes or two watershed_keys; no side channel's watershed_key line is itself a side channel; one watershed code has two main lines (Beaver River 359572098 / 359024601); FWA lines are digitized from the downstream end (M = 0); 0 multipart segments.

## `fwa_indexpoint()` keeps one segment per stream, then you filter

It returns the nearest segment per blue line and can exclude only edge type 6010. Filtering its output afterwards drops the whole stream when that nearest segment is unusable. On 38,729 PCIC outlets (150 m, 5 streams): 651 streams lost that had a usable segment in reach; causes were segments with no `fwa_streams_watersheds_lut` row (7,157 candidates; 6,822 have no local code), `999.*` codes (634) and edge 1425 (8). Running the same search with the filters before the per-stream pick avoids it (`pcic_crosswalk02_candidates.sql`). See also fresh `research/fwa_point_snap.md`.

## Not fixed: area lookup at tributary mouths

`fwa_streams_watersheds_lut` can give a tributary-mouth segment the fundamental watershed of the stream it joins, so upstream area there is the parent's. In the PCIC build, 2,184 of 36,380 sub-basins got no local area of their own (8% of local runoff appears only at their outlet).
