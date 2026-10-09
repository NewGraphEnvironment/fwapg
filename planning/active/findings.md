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
