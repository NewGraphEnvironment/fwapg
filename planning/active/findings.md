# Findings — PCIC crosswalk: Nechako Reservoir outlets unplaced (#24)

## Issue context

**If we do it:** FWA segments in the Nechako Reservoir groups carry PCIC's routed flow, instead of about zero. **If we never do:** routed flow there is about zero on every segment, so any consumer (wet's default pick, NewGraphEnvironment/wet#57) has to fall back to another estimate across four watershed groups.

## What happens

In LEUT, UEUT and UNRS, routed flow in `fwa_stream_networks_discharge_monthly` is under 1 % of wet's open water balance on 97–100 % of segments, and LNRS is close behind. These four groups hold 73 % of the Fraser's near-zero routed segments (measured for wet#57 against fwapg 341b078, the #14 build).

PCIC has 487 outlets in the four groups (`fwapg.pcic_outlets` intersected with `fwa_watershed_groups_poly`):

| group | PCIC outlets | placed | flags |
|---|---|---|---|
| LEUT | 72 | 0 | broken_chain |
| UEUT | 203 | 0 | broken_chain, no_candidate |
| UNRS | 111 | 1 | broken_chain |
| LNRS | 101 | 3 | broken_chain |

PCIC's tree takes all 386 outlets of LEUT, UEUT and UNRS to the Fraser (root 4009421), and their `anchor_subid` lies in CHES. That suggests PCIC routes the reservoir out through the Skins Lake spillway and the Cheslatta, while the FWA reservoir drains another way. The chain breaks, the outlets stay unplaced, and their local runoff is given to the Cheslatta anchor's sub-basin. The FWA segments in the reservoir get almost none.

This is the "Nechako reservoir lakes" case in #6's gauge disagreements: wet's #58 report lists 08JA014, 08JA015, 08JA016 and 08JA028 at about 0 m³/s routed.

## Proposed

- Confirm the FWA's outlet of the reservoir, and PCIC's (`dowsubid` at the reservoir's lowest outlets).
- Decide how placement treats a reservoir both networks hold but drain differently. One option: give the reservoir's runoff to the FWA reservoir's own segments, and pass it on to whichever placed outlet the FWA reaches, so flow follows the FWA as the README says it does elsewhere.
- Check the regulated-flow flag on the Cheslatta (README, drainage check) against the result.

Relates to #6, #8.


## Errors Encountered

| Error | Resolution |
|-------|------------|
| Dev build 1 (46fcf91) stopped at step 3 after 23 min: `invalid reference to FROM-clause entry for table "dv"` (an `UPDATE ... FROM x, LATERAL (... dv ...)` cannot see the target table) | Exit derived in a subquery that joins `pcic_diversions` itself; refusals probed with a non-lake subid and a wrong blue line, both raise |

## Baseline (2026-10-27, crosswalk b1a710836df2cafea0ef514b7ed1c338, PNWNAmet 1951-2012)

Produced by `logs/nechako_measure.sql` (`logs/20261027_baseline_1951-2012.out`); gauges from the build's
`data/qa_gauges_*.csv` (`logs/20261027_baseline_gauges.csv`).

- Outlets with their PCIC point in the group, placed: LEUT 0/72, UEUT 0/203 (4 no_candidate), UNRS 1/111,
  LNRS 3/101, CHES 95/95. The 479 broken-chain outlets of the four groups are all anchored to 1007550.
- Mean annual specific runoff over FWA upstream area, median per group: LEUT 0.3 mm/yr, UEUT 0.3, UNRS 0.2,
  LNRS 0.3, CHES 131.1. Segments under 5 mm/yr: LEUT 100%, UEUT 100%, UNRS 100%, LNRS 97.3%, CHES 1.0%.
  (5 mm/yr stands in for "under 1% of wet's water balance": the regional runoff is several hundred mm.)
- Key points, mean annual m³/s: Whitesail Lake 0.003, Ootsa Lake 0.037, Natalkuz 0.045, Knewstubb mid 0.128,
  Knewstubb exit segment 701799415 0.134, canyon below Kenney Dam 0.134, Nechako above the Cheslatta 0.365
  (all sub-basin 1002307), Skins Lake spillway line top 156.365 (1007550), Cheslatta near its mouth 161.611,
  Nechako below the Cheslatta 161.976.
- Gauges, FWA against PCIC: 08JA013 (spillway) 156.365 vs 156.366; 08JA017 162.170 vs 162.170; 08JA015 0.001
  vs 3.905; 08JA016 0.001 vs 0.684; 08JA028 0.024 vs 44.962; 08JA014 no PCIC outlet. Observed at 08JA013
  95.5 and 08JA017 73.3 (1951-2012): PCIC models no Kemano diversion.
- Other anchors collecting many unplaced outlets, all inside BC: Kootenay 5025228 (140), Pend-d'Oreille
  5013906 (92), Fox 206008363 (44), KOTL 5014312 (32), Chilcotin 4007152 (31). Out of scope (Phase 7 issue).
- The reservoir exit: segment 701799415 (edge 1200, Knewstubb Lake 329318438) at 288,852.348 m on
  356362759, 70.7 km from PCIC's lake outlet point (on Ootsa Lake's shore at the spillway).

## Dev build and mutation checks (2026-10-27)

Dev build 2 (e4a4d91, monthly 1951-2012, from a scratch worktree whose `qa.sql` ended in a failing line):
15:43:26Z to 16:20:07Z (36 min 41 s); every QA test `t`, the seven new ones included; only the hold line `f`, so
the staging tables were kept. (Dev build 1, at 46fcf91, failed at 03_diversions: Errors below.)

Mutation checks (`logs/mutation_checks.sh`, `logs/20261027_mutation_checks.out`), on that staging, 16:20-16:32Z.
Each defect applied to a copy of the SQL (refused unless it matched once), run on the groups it touches, and undone
by rerunning the real SQL:

| mutation | tests that read f |
|---|---|
| M1: 07 does not add the diverted outlet at its PCIC ancestor's segment (CHES) | outlet segments carry accumulated flow; Nechako weights; exactly one segment |
| M2: 07 joins children by flow parent, not position (LNRS) | Nechako weights (canyon share) |
| M3: 06 takes the diversion's area off its flow parent | area comes off its position parent |
| M4: 06 leaves the diversion's flow on its position parent | every diversion placed ... position and flow parents |
| M5: no diversion listed, placement rerun (not undone) | every diversion placed; Nechako groups placed >= 90% |

After the undo of M1-M4 every test was `t` again. Not mutated, as there is nothing to observe today (plan review 1):
05's exemption (no child can break against the exit) and 06's move skip (no junction at the exit).

The old build's staging is gone, so the new tests cannot be run on it (plan review 8). Its "before" is the
baseline above: exit 0.134 m³/s against PCIC's 156, 4 of 483 outlets with a candidate placed.

## Code check (`/code-check branch`, ce4add3...HEAD)

| Round | Findings | Fixed | Accepted | Inside previous fix? |
|-------|----------|-------|----------|----------------------|
| 1 | 0 (2 notes) | 2 notes | 0 | — |
| 2 | 1 fragile (area test, flow-parent side, a proxy) + 3 notes | 1 + 2 notes | 1 note (sort order kept comparable) | n |
| 3 | 2 fragile (area test, position-parent side; guard 2 message) | 2, plus a refusal for a line joining at the exit vertex | guard 3 stricter than needed (commented) | y (the other half of round 2's fix) |
| 4 | 0 | — | README sentence looser than the refusals (tightened in Phase 4) | n |

Ended by enumeration: round 3 listed every place the mechanism (checks validated against the Nechako's sizes,
counts or geometry rather than the property) reaches, 20 rows; round 4 walked each row against the code after the
fixes (`review-round4.md`): each holds for any listed diversion, refuses loudly, or is Nechako-specific by design.
Round 4 added two rows: 06's cycle check reachable through a diversion placed above its own ancestor (loud, does not
name the diversion), and the area test's inner joins (cannot drop a row today: every lut row has an area).
Spend: five reviewer agents with the plan review, the per-task bound.
