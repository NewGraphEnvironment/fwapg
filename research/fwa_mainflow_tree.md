# A dendritic subset of the FWA stream network

**Verified:** 2026-10-11 (the tree and SSNbler), 2026-11-20 (upstream area) · **Issues:** NewGraphEnvironment/fwapg#2 (spawned from two hand-built SSN2 stream-temperature networks), #4 (upstream area on the tree), #13 (end-to-end run, SSNbler on whole basins), #16 (SSNbler fixed on a fork, re-run), pet221/SSNbler#8 (SSNbler's false errors), pet221/SSNbler#9 (the fork's fixes as a pull request, closed 2026-10-22: the maintainer asked to discuss in #8 first, and has taken #8 on), #19 (every watershed group on the fork) · **Produced by:** the SQL of `extras/mainflow_tree` and `extras/blue_line_paths`, run step by step on a full provincial fwapg (4,907,441 segments) in #2 and as the committed job scripts in #13 (identical tree); measurements in `planning/archive/2026-10-issue-2-mainflow-tree/`, `planning/archive/2026-10-issue-13-extras-end-to-end/` and `planning/archive/2026-10-issue-16-ssnbler-fork/`; the area by `extras/mainflow_tree/sql/mainflow_tree_area.sql` and `sql/qa_area.sql` (#4), measurements in that issue's planning archive

## The FWA is not a tree, and the obvious subsets are not either

Braids and side channels are mapped as secondary flow, so 74,426 nodes province-wide are the upstream end of more than one segment (water leaves them two ways). A spatial stream network model (SSNbler/SSN2) rejects that.

- **Dropping the secondary-flow edge types** (1100/1150/1300/1350) leaves splits (18-475 per group in 14 Skeena/Nechako groups, edge type 1425 excluded; measured in the issue) and cuts tributaries off (30-1,513 per group): edge types do not mark the tree.
- **Main flow** (`blue_line_key = watershed_key`) has no splits, but on its own leaves 28,870 segments cut off province-wide: tributaries whose mouth is on a side channel (28,824 main-flow lines drain through one).
- **Edge type 1450 is not secondary flow.** Connectors at the mouth of a line are part of that line; 24 of 26 that one hand-built network had to add back were main flow already.

## What works

Main flow, plus each side channel a main-flow line drains through, kept from where that water enters down to the side channel's mouth (recursively, since side channels drain into other side channels). The part of a side channel above its highest entry is left out, so no split is introduced. Which side channel a line drains through and where comes from the blue line downstream paths (`fwa_position_codes.md`), not from local codes or edge types.

Three additions were needed after measuring, each for a class the paths get right for flow but wrong for topology:

| left by reattachment alone | cause | fix |
|---|---|---|
| 6 splits | a tributary whose mouth is on a main-flow node was given, as parent, a side channel 0.7-1 m away near its top (the 1 m touch tolerance) | do not reattach a line whose mouth is already on a main-flow node |
| 97 cut-offs | the junction in the paths is not where the mouth is: 33 deferred code junctions and 32 side-channel fallbacks more than 1 m away, 21 touches within 1 m, 11 lines with no parent | follow a cut-off down the network while there is exactly one way down (177 segments on 110 lines) |
| 1 split | the Beaver River: one watershed code, two `watershed_key` lines, whose 6010 connectors leave one node | override (`overrides.csv`) |

Result: 4,510,368 segments, **0 splits, 8 cut-offs, 473 dead ends**. Each remaining cut-off is a segment added by following whose downstream node has two ways down; following does not choose between them. A dead end is a mouth that touches no network segment although the paths give its line a parent: 354 main stems off their code junction, 119 side channels reached by a fallback junction. They are gaps in the FWA geometry, not in the rule, and each adds an outlet to a subset that holds it; so do 23 mouths inside BC on lines the paths give no parent (11 main-flow, 12 side channels: a gap in the paths or a closed basin). The other 26,690 mouths with no parent lie within 50 m of BC's edge, the coast or a land border. The Nechako basin has 8 outlets (its mouth, 6 dead ends and one side channel with no parent inside BC), the Skeena 1.

A float detail that matters: a junction measure located on the geometry (`drm + ST_LineLocatePoint * length`) can land up to 1.5e-4 m above the node where the next segment starts, so "segments below the entry" needs a tolerance (1 cm), or the segment above the entry is kept: 366 splits in the plan review's province-wide emulation with a strict `<`.

## Flow direction

FWA digitizes side channels like main flow, from the downstream end (measure 0). A tree subset reversed as a whole is in the direction of flow, with no per-segment exceptions. The exceptions a hand-built network needed came from routing two tributaries *up* a side channel to where it leaves the river.

SSNbler (`lines_to_lsn(check_topology = TRUE)`, 1.1.2) on the Skeena and Nechako groups, every line reversed: 0 node errors in 27 of 29 groups, including LSKE, which holds the fourth test side channel. The other two groups report one spot each, a main-flow segment of 1.6 or 2.9 cm whose geometry is a plain chain; those errors are SSNbler's, not the tree's (below). Whole basins: the Nechako has 0 node errors and the 8 outlets counted in SQL; the Skeena 1 outlet. With both SSNbler defects fixed (fork at 37ca338, #16), USKE, MSKE and the whole Skeena have 0 node errors, the Skeena 1 outlet and one relationship per non-outlet edge, none splitting.

Three SSNbler facts matter for anyone repeating this.
- **Its two code paths cost differently.** Below 46,340 lines it runs serially and memory grows with the square of the line count (1.1.2: 28 GB at 21,700 lines, 52-54 GB at 30,000; the fork: 17-18 GB at 21,700), so a basin is checked a watershed group at a time and never several at once: three at once caused kernel panics on a 64 GB machine. At 46,340 or more it must run in parallel, in chunks of up to 500 nodes, and memory grows about linearly (1.1.2: 3.5 GB at 52,000 lines, 16 GB for the Nechako's 210,000, 20 GB in 35 min for the Skeena's 262,000; the fork: 10.9 GB for the Skeena, but 54 min).
- **Its distances lose centimetres at BC Albers coordinates (1.1.2).** They come from `pdist::pdist()`, which rounds each coordinate to single precision (`as.single()`, then C `float`) before subtracting, so two points read as 0 apart whenever their x and their y each round to the same float. Float spacing grows with magnitude (0.0625 m at 10⁶ m, 0.125 m at BC Albers northings above 1,048,576 m), and measured over random pairs the error grows in proportion to the coordinates (9 mm at 10⁵ m, 1.6 cm at 2×10⁵ m). A segment a few cm long then reads as an unsnapped node and a divergence at each end, and its edges are joined wrongly. That is what the USKE and MSKE errors were. Shifting to a local origin only narrows the error to the data's own extent (two shifts each left one error in one group), so the fork computes distances in double precision instead. A pull request with the fork's fixes (pet221/SSNbler#9) was closed on 2026-10-22: the maintainer asked to discuss in the issue first, and has taken #8 on. Reported as pet221/SSNbler#8, with a synthetic reprex (`extras/mainflow_tree/ssnbler_reprex.R`).
- **The parallel path's unsnapped flags land on the wrong nodes (1.1.2).** The duplicate test sees only a chunk's rows, and the row numbers it returns are the chunk's, applied to the whole node list without an offset (`pdist_node_coords`, `get_pdist_nodes`, `lines_to_lsn`). The whole Skeena flagged two exact nodes in ZYMO: they are rows 462 and 463 of the chunk holding MSKE's segment ends. USKE's two ends fall in different chunks and were not flagged at all. The defect needs the precision loss to fire: nodes are deduplicated before the check, so with exact distances no end is at distance 0 from two nodes. The fork fixes it anyway and tests the chunk combiner directly.
- **It rounds node coordinates** to one decimal place fewer than `snap_tolerance` (10 m at its default of 0), so the tolerance has to be set (0.001 gives 1 cm).

## Upstream area on the tree

Measured 2026-11-20 on the 2026-10 tree (4,510,368 segments, 3,245,453 watershed polygons).

**Neither FWA source gives an area that is additive along the tree.**

- The watershed lookup (`fwa_streams_watersheds_lut` with `fwa_watersheds_upstream_area`) matches a segment to a polygon by its codes and takes every polygon `FWA_Upstream` puts above that polygon. A side channel carries its river's watershed code, so every reattached segment gets its river's area: 4.26 to 5.11 million ha on four Skeena side channels whose entering tributaries have 51,420 to 302,611 ha. A tributary's mouth segment inside its river's polygon gets the river's area too (8,111 tree segments are matched to a polygon of another stream's code), 71,402 are matched to a polygon on their own stream at another local code, and 2,941 have no row.
- `FWA_WatershedAtMeasure()` returns no upstream area at a point on a segment with no local watershed code (158,188 network segments, side channels above their highest entry among them): `FWA_Upstream` is NULL for a NULL local code, so nothing upstream is collected and the answer is only the slice of the river polygon at the point, or no row where the slice is empty (#52). Lower on a side channel it returns the whole river.

**What works: give each polygon to one tree segment and sum down the tree.** The polygon's place follows `FWA_Upstream` itself (area at the polygon's outlet), so plain main flow reproduces the lookup. Three things had to be added to that, each measured:

| left by the plain rule | cause | fix |
|---|---|---|
| 17,478 main-flow segments (8,601 km) with no area | a reach with no polygon of its own code pair lies in the polygon coded at a lower local code on its stream, and the plain rule puts that polygon at the top of the lower reach | the polygon goes to the top of the run of reaches up to the next local code that has a polygon |
| about 1,000 segments on 782 streams with no area | streams with no polygon at all, lying in another stream's polygon | a share of that polygon by length (869 segments after the fix above; an estimate) |
| differences from the lookup with nothing routed differently | 1,457 polygons (45,175 ha) have a local code that is not under their own watershed code; `FWA_Upstream` has guards on the local code in two of its three cases, so the lookup leaves such a polygon out at its stream's mouth reach and on every ancestor the local code is not under, and counts it elsewhere | they are placed at their stream's mouth, and classed |

Local codes do not always rise along a line, and a pair can reappear further up: the run taken is the lowest that holds the pair, and a connector with no local code (edge type 6010) must not end a run (it did in the first build: segments above the connector missed their polygon, and the segments needing a length share fell from 1,171 to 869 once it was fixed).

**Gaps.** Of the 473 dead ends and 8 cut-offs, 90 and 7 reach the tree further down through the blue line paths and their area is carried there. The other 383 dead ends and 1 cut-off have no tree segment below them on any line of their path: the network ends there. They drain 184,742 ha, the largest 50,535 ha, and stay outlets.

**Cost.** About 5 min province-wide in SQL. The sum is a loop from the deepest level of the tree to the outlets, one statement a level, with an index on depth: 4,380 levels in about 20 s. A depth this large (a segment is up to 4,380 steps from its outlet) is why the per-level statement must not scan the table.

**Checking it against the lookup without reading the areas.** The lookup routes by codes and the tree by nodes, so the two can only differ where something upstream is routed differently. Each such thing (a line whose mouth is on a side channel, at an outlet, across a gap, or elsewhere than its code says; a polygon on a side channel; a length share; a polygon with a bad code) is counted for every segment it passes down the tree and for every segment its codes put below it. Of 4,362,376 comparable main-flow segments, 4,290,355 have equal counts and all but 337 of those equal the lookup; of the 72,021 with unequal counts, 71,748 differ. Of the 337: 155 are lookup rows that are not what the lookup's own definition gives now (the tree equals the definition), 165 are segments whose own local code is more than one level below or not under their watershed code, and 17 on 11 lines are not explained. A class defined for a whole stream ("local codes out of order somewhere on it") took the Fraser, Skeena, Stikine and Nechako main stems out of the comparison; per segment it is 836.

## Not settled

- The 17 main-flow segments that differ from the lookup with nothing routed differently and no anomaly in their codes (#4).
- The paths' 1 m touch tolerance is right for flow (PCIC) and too loose for topology; the tree compensates with node tests rather than changing the shared paths.
