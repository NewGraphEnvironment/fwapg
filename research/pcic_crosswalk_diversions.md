# PCIC crosswalk: lakes that PCIC and the FWA drain by different routes

**Verified:** 2026-10-27 · **Issues:** NewGraphEnvironment/fwapg#24 (the Nechako Reservoir); spawned #46 (the other large clusters of unplaced outlets) · **Produced by:** `extras/pcic_crosswalk/pcic_crosswalk.sh` for PNWNAmet historical 1981-2010 (`WEEKLY=1`) and 1951-2012, measured with `planning/archive/2026-10-issue-24-pcic-nechako-diversion/logs/` (`nechako_measure.sql`, `compare_published.sh`, the mutation checks and their outputs)

## The case

PCIC's hydromosaic has one lake outlet for the whole Nechako Reservoir, 1007550, and routes it out
through the Skins Lake spillway and the Cheslatta River (its PCIC parent chain: 1008709 at the spillway
gauge 08JA013, then the Cheslatta, then the Nechako below Cheslatta Falls). That is the regulated
route since Kenney Dam closed in 1952. The FWA has the natural route: the reservoir's main line
(blue line 356362759) leaves Knewstubb Lake (waterbody 329318438) at segment 701799415, 288,852.348 m,
and runs down the Nechako canyon to the Cheslatta confluence at 280,379 m. The FWA does not connect the
spillway line (356209076) to the reservoir: it starts 62 m from Ootsa Lake.

Placement keeps PCIC's chain on the FWA: every outlet must sit on or upstream of the nearest placed
outlet below it. 1007550's nearest candidate was the top of the spillway line, so it was placed there,
and nothing in the reservoir is upstream of that line on the FWA. In the build before the fix
(crosswalk b1a71083, 1951-2012), 479 outlets above 1007550 were `broken_chain` (4 more have no
candidate): LEUT 0/72 placed, UEUT 0/203, UNRS 1/111, LNRS 3/101. Their runoff still went to 1007550's
sub-basin and down the Cheslatta, so the spillway matched PCIC (156.365 against 156.366 m³/s). The
reservoir's own segments belonged to the nearest placed outlet on or below them, 1002307 on the Nechako
at 280,461.5 m, which carries 0.36 m³/s of local runoff: they read about 0 (median specific runoff
0.2-0.3 mm/yr in the four groups; Knewstubb's exit 0.134 m³/s; gauges 08JA015, 08JA016 and 08JA028 at
0.001, 0.001 and 0.024 against PCIC's 3.905, 0.684 and 44.962).

## The mechanism: a hand-listed diversion

`sql/pcic_crosswalk03_diversions.sql` lists the outlet, the FWA line that drains the lake and the lake.
For each listed outlet:

- **Position.** It is placed at the FWA's exit from the lake (the lake's lowest segment on that line),
  whatever its anchor says, and is never demoted or moved below a junction. Its PCIC children are then
  chain-tested against that position as usual, so the outlets above place normally.
- **Two parents.** Its position gives it an FWA parent, the nearest placed outlet below the exit (for
  1007550, 1002307 in the canyon): this is the *position parent*, kept in `fwapg.pcic_qa_diversions`.
  Its flow goes to its nearest placed PCIC ancestor (1008709): this is its `fwa_parent_subid`, the
  published flow parent. Flow accumulates down `fwa_parent_subid`, so the reservoir reaches the
  Cheslatta.
- **Area.** A sub-basin's local area is its upstream area less that of the outlets whose position
  drains to it. So the reservoir's 13,999 km² comes off the canyon sub-basin (1002307, local area
  3,117 ha after) and not off the spillway's (1008709, 84 ha).
- **Weights.** Segments join children by position parent for area, and by flow parent for
  `upstream_subids`. The canyon's segments lose the reservoir's area from their share and do not carry
  its flow. The diversion is added to `upstream_subids` of its flow parent's own segment, where its water
  enters, and of no other segment.

The refusals: an outlet that is not a PCIC lake outlet with a series; an exit placement could not use
(subsurface, off the network, no local code, no fundamental watershed); another line joining at the
exit vertex (it would be parented below the diversion, which is never moved); a position parent that is
missing or is the flow parent itself (one placed outlet on both routes would be counted twice); and a
receiving outlet that is not the highest placed outlet on its segment (stricter than needed).

## What it changed

1981-2010 (crosswalk 901d1271), against the old build:

| | before | after |
|---|---|---|
| placed, LEUT / UEUT / UNRS / LNRS / CHES | 0/72, 0/203, 1/111, 3/101, 95/95 | 72/72, 199/203, 111/111, 101/101, 95/95 |
| median specific runoff (mm/yr), same order | 0.3, 0.3, 0.2, 0.3, 131.1 | 353.3, 357.9, 385.5, 139.6, 125.3 |
| segments under 5 mm/yr | 100%, 100%, 100%, 97.3%, 1.0% | 0.4%, 0.2%, 0.1%, 0.3%, 0.5% |
| Knewstubb exit (m³/s) | 0.134 | 155.832 |
| 08JA015 / 08JA016 / 08JA028, FWA over PCIC | 0.000 / 0.001 / 0.001 | 1.000 / 1.000 / 1.000 |
| 08JA013 / 08JA017, FWA over PCIC | 1.000 / 1.000 | 1.000 / 1.000 |

The "before" placements and runoff are the 1951-2012 baseline; the gauge ratios are the old build's
1981-2010. The 4 unplaced in UEUT have no candidate. The 1951-2012 rebuild has the same crosswalk and the
same picture: the exit carries 156.365 m³/s against PCIC's 156.366 (was 0.134), and FWA flow is within 10%
of PCIC's at 497 of 538 gauges (was 494; the three are 08JA015, 08JA016 and 08JA028). Segment-months
clamped at zero rose from 0.94% to 1.04%, all inside the five groups: the newly placed lake outlets have
negative local runoff in some freshet months, as outlets elsewhere do.

Outside the reservoir nothing moved: against the published files, crosswalk rows differ for the 484
outlets of 1007550's PCIC subtree only, sub-basin days for 480 subtree sub-basins only, and weights
outside the five groups at one segment (the top of a reservoir tributary that crosses into CHIL, now in a
newly placed outlet's sub-basin). 1,204 more weights differ only in the order of `upstream_subids`:
07's `array_agg` has no ORDER BY, so a rebuild can reorder the array without changing any flow.

PCIC models no Kemano diversion, so below the reservoir its flow is high, and the crosswalk carries
PCIC's error faithfully: at 08JA013 PCIC is 1.64 times observed over 1951-2012 (2.37 over 1981-2010),
at 08JA017 2.21 (2.33).

## Proved by

`qa.sql` tests every diversion's position and both parents; ≥ 90% of the Nechako groups' outlets with a
candidate placed; the exit carrying 1007550's PCIC flow, 1008709 within 5% and the canyon under 1 m³/s;
the area taken off the position parent and not the flow parent, by definition; the canyon's share and
the spillway's `upstream_subids`; each diversion in exactly one segment's `upstream_subids`; and the
Eutsuk outlet 1001917 within 5% of PCIC. Each was shown to fail on its defect restored (mutations M1-M5
on a held dev build, and the area test's three wrong area statements on a rebuilt scratch schema).

## Other candidates

The same symptom, many outlets unplaced behind one anchor, appears elsewhere in BC: Kootenay 5025228
(140 outlets), Pend-d'Oreille 5013906 (92), Fox 206008363 (44), KOTL 5014312 (32), Chilcotin 4007152
(31). Whether any is a lake drained by two routes, or a different case, is #46. A new listing is one
row in `pcic_crosswalk03_diversions.sql`; the refusals say what it must satisfy.
