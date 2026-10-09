# Findings — PCIC crosswalk: drainage check at every placed outlet (#7)

## Issue context

**If we do it:** every placed PCIC outlet gets an independent check that it sits on the right FWA stream, including the case the flow-agreement test cannot see: a whole PCIC tributary chain placed consistently on a parallel FWA tributary. **If we never do:** that failure stays unmeasured, and confidence in the crosswalk rests on snap distance (p50 5.8 m) and agreement with PCIC's own outflow (99.1% within 5%).

## Problem
`extras/pcic_crosswalk` (#5, PR #6) is checked by internal consistency: flow accumulated on the FWA matches PCIC's outflow where the two networks agree. That is partly circular. If a chain of outlets is shifted onto a neighbouring FWA stream, runoff is relocated but still sums correctly. PCIC publishes no sub-basin polygons or areas (`bbox-server/collections/upstreams` gives a point and `upstream_subids` only), so there is no PCIC drainage area to compare with FWA upstream area directly.

## Proposed solution
A QA report (and a test with a ceiling once the distribution is known) comparing, at each placed outlet:
- [ ] PCIC upstream network length: summed length of PCIC river segments in the outlet's PCIC subtree (from `data/rivers.geojson` and the dowsubid tree)
- [ ] FWA upstream network length at the placed position (main-flow edges upstream, via the blue-line paths)
- [ ] The ratio, normalised by its median over the outlet's watershed group (PCIC's network is coarser than the FWA, so the ratio is not 1, but it should be stable regionally)
- [ ] Outliers (say > 2× or < 0.5× the regional median) listed with their snap distance, candidate rank and flag, and checked against #8
- [ ] Alternative to try if length is too noisy: FWA upstream area at the placed position against FWA upstream area at the PCIC outlet's own snap point (no chain constraint) — a disagreement means the chain moved the outlet.

Not yet offered upstream.

## Measurements (2026-10-09, local fresh-db, rebuild of the #5 final placement: 37,667 placed)

- **Density proxy** (PCIC upstream river length / FWA upstream area, WSG-median normalised): median 1.0, but the low tail is headwater-biased. Of 1,621 outlets < 0.2, 1,135 have < 5 km of PCIC river upstream (FWA area includes ground above the tip of PCIC's network). For subtrees ≥ 5 km the median is ~1.0 and the tails are clean.
- **Runoff proxy** (PCIC mean flow / FWA area, WSG-median normalised): no headwater bias (medians 0.82–0.98 for the smallest subtrees) but noisier: 1,373 < 0.2, 570 > 5.
- **Both agreeing** cuts false flags. All placements: 639 small / 126 big. Most of the extra small were **side channels**: the watershed lookup gives a side channel its main river's polygon (Maria Slough 217,390 km²), so area is meaningless there → check main stems only.
- **Main stems only (final):** 218 `small`, 124 `big` of 37,040. 82 of the 85 outlets > 10× PCIC are `small` (all 85 are on main stems). By edge type, small: 1250 double-line river 100, 1410 lake connector 44, 1000 41, 1050 14, 1450 12, 1200 7; big: 1000 60, 1250 24, 1450 23, 1410 12.
- **Sampled flags:** small = tributary outlets on lake connector lines (FWA area = lake catchment) and on double-line rivers (likely real), plus dry interior creeks with a sparse PCIC network (Meldrum Creek 0.02 m³/s on 178 km², possibly genuine); big = large PCIC outlets on segments the lookup gives a tiny polygon (double-line river construction lines; Lord River 115 km of PCIC river on 0.13 km²) and regulated flow (Cheslatta River: Nechako Reservoir releases).
- **Seeded errors:** Nicola main stem 3000039 put back on Clapperton Creek → `big`. 200/200 small outlets moved onto a candidate with ≥ 10× area → flagged; 198/200 big outlets moved onto ≤ 1/10 → flagged. Not caught: a wrong stream of similar size (< ~5×) — #8's visual review.
- **Lut mismatch** (placed segment's fundamental watershed has another stream's code): only 206 outlets; not the main cause of anything.
- Cost: 18 s.
- **Against the gauges:** of 493 placed PCIC outlets at agreeing gauges, 4 are flagged (3 small, 1 big); of 28 at disagreeing gauges, none. The checks are complementary: gauge disagreements come from broken chains and the check's own PCIC-side pick, not from outlets on the wrong-sized stream.
- **Code-check (3 rounds):** R1 — the ceiling test could pass vacuously when ratios were NULL → `unmeasured` flag, required 0; stale header counts; small groups → province median (< 20 placements; no flags changed). R2 — clean. R3 — enumerated 15 fail-toward-pass sites; one unsafe: a lake-only PCIC subtree has length 0 (not NULL), so density is 0 by construction and such outlets could never be `big` (83 outlets; 3007696 at 274.7x runoff read `ok`) → judged by runoff alone, `judged_by` column. Final: 218 `small`, 126 `big` (4 runoff-only), 0 `unmeasured`.
