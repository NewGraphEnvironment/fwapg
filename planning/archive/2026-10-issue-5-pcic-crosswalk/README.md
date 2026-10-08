## Outcome
Built `extras/pcic_crosswalk/`: PCIC hydromosaic's ~48,700 sub-basin outlets (Raven-routed PNWNAmet streamflow, 1951-2012 monthly means) placed on the FWA so PCIC's routing chain holds, and monthly flow written for every FWA segment below or within PCIC's network (`fwa_stream_networks_discharge_monthly`, plus `pcic_fwa_crosswalk`). The main lesson: FWA local codes cannot order positions (`FWA_Upstream` across blue lines). Six code-check rounds converged only once every position comparison moved to a per-blue-line downstream path with code-equality and touch-based junctions — see [research/fwa_position_codes.md](../../../research/fwa_position_codes.md). Flow is PCIC local runoff injected at placed outlets and accumulated down the FWA tree, which conserves mass and equals PCIC's outflow wherever the two networks agree. Also learned: the issue's API paths were wrong (`bbox-server` is at the host root); a bulk NetCDF endpoint exists (one domain per request, 422 on mixed); GNU parallel is not installed on the dev machine (moreutils shadows it), so the job uses `xargs -P`; and post-filtering `fwa_indexpoint()` drops whole streams.

## Measurement
Final build on local fresh-db (2026-10-08):
- 48,716 PCIC outlets (48,261 rivers, 455 lakes); 28 with no series. Placed 36,527; no FWA candidate within 150 m 9,993 (mostly outside BC); broken chain 2,075; demoted 93.
- Snap distance of placed outlets: p50 5.8 m, p90 12.7 m.
- 3,375,280 FWA segments × 12 months (40,503,360 rows; 217 MB gz).
- Accumulated flow on the FWA within 5% of PCIC's outflow at 99.1% of placed outlets, 99.9% of outlets > 100 m³/s. Columbia (5024140, 5025132) and Birkenhead (4008011) equal PCIC.
- Flow drops > 10% between consecutive segments (q > 10 m³/s): 9 of 88,200 main-stem pairs, 1 of 1,051 side-channel pairs.
- Gauge 08EE003 Bulkley near Houston: FWA area 2,315 vs 2,319 km²; freshet months 0.87-1.41× observed, low flows 1.2-1.7× high.
- Limitation kept: 2,184 sub-basins (8% of local runoff) have no local area because of the watershed lookup at tributary mouths.
Wrong turns, kept for the record: snapping the junction point itself (tributary mouths won at confluences); local-code repair (copied bad codes); collecting flow by FWA nesting with PCIC outflows (double counting); demoting on PCIC/FWA disagreement (unplaced whole tributaries); unbounded geometric junctions (Okanagan on the Columbia in BC); same-main-only side channels (17,200 braids orphaned).

### Gauge validation (after the PR opened, 2026-10-08)
`extras/pcic_crosswalk/qa_gauges.sh` over 538 WSC gauges (PCIC flow at the nearest PCIC segment vs FWA flow at the gauge). The first run found three misplacement classes the internal tests could not see, each fixed and re-measured:
- Nicola main stem placed on Clapperton Creek: the one-level look-ahead counted a child's 86 m fallback candidate as a tie with its 8.9 m Nicola candidate. Restricting to near candidates (≤ nearest + 25 m) fixed it but put an upper Columbia outlet on a parallel channel coded as a tributary; replaced by a three-level vote of descendants' near candidates.
- Upper Columbia (Columbia Wetlands) outlets placed on side channels, leaving ~230 main-stem outlets unplaceable. First fix (move side-channel candidates to the main stem) was wrong: code-check round 7 (`review-round7.md`) showed FWA often codes a tributary's last reach as a side channel of the river it joins, and the move put 326 tributary outlets on the big river (outlets > 10× PCIC: ~24 → 358). Final: keep the side-channel candidate, add the main-stem point as another, and let the vote choose, with the added point as "near" as its side channel. A "largest PCIC child" rule was tried in between and misfired on tributaries of tributaries (Ansedagan).
- The check's own flaws: nearest PCIC segment is sometimes the other branch at a confluence (now reported separately), and area-matched snaps can pick a side channel (main stem preferred within 10% area).
Result: placed 36,527 → 37,667; broken chain 2,075 → 985; within 5% of PCIC 99.1% → 99.0%; outlets > 10× PCIC ~24 → 85 (81 of them receive water from placed outlets PCIC says are not upstream; median PCIC 0.48 vs FWA 38.5 m³/s). Gauges: FWA within 10% of PCIC at 494 of 538, 11 ambiguous, 33 disagree. Known cases (Spillimacheen distributary, Ansedagan Creek, the 85) moved to `qa_report.sql` and #8; the > 10× test kept as a regression ceiling of 100.

## Evidence
Review findings: `review-round*.md` in this directory. Build logs (local, not tracked): `extras/pcic_crosswalk/data/build*.log`, `data/export.log`.

Closed by: PR into `newgraph` (see branch `5-pcic-routed-streamflow-on-fwa-streams-cr`)
