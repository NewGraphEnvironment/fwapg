# A dendritic subset of the FWA stream network

**Verified:** 2026-10-09 · **Issues:** NewGraphEnvironment/fwapg#2 (spawned from two hand-built SSN2 stream-temperature networks), #4 (area on reattached segments) · **Produced by:** `extras/mainflow_tree/mainflow_tree.sh` on a full provincial fwapg (4,907,441 segments); measurements in `planning/archive/2026-10-issue-2-mainflow-tree/`

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

Result: 4,510,368 segments, **0 splits, 8 cut-offs, 473 dead ends**. Each remaining cut-off is a reattached side channel whose downstream node has two ways down; following does not choose between them. A dead end is a mouth that touches no network segment although the paths give its line a parent: 354 main stems off their code junction, 119 side channels reached by a fallback junction. They are gaps in the FWA geometry, not in the rule, and each adds an outlet to a subset that holds it: the Nechako basin has 8 outlets (its mouth and 7 side-channel dead ends in the reservoir groups), the Skeena 1.

A float detail that matters: a junction measure located on the geometry (`drm + ST_LineLocatePoint * length`) can land up to 1.5e-4 m above the node where the next segment starts, so "segments below the entry" needs a tolerance (1 cm), or the segment above the entry is kept: 366 splits in the plan review's province-wide emulation with a strict `<`.

## Flow direction

FWA digitizes side channels like main flow, from the downstream end (measure 0). A tree subset reversed as a whole is in the direction of flow, with no per-segment exceptions. The exceptions a hand-built network needed came from routing two tributaries *up* a side channel to where it leaves the river.

SSNbler (`lines_to_lsn(check_topology = TRUE)`, 1.1.2) on the Skeena and Nechako groups, every line reversed: 0 node errors in 24 of 26 groups. The other two report one spot each, a main-flow segment of 1.6 or 2.9 cm whose geometry is a plain chain. Two SSNbler facts matter for anyone repeating this. Its memory grows roughly with the square of the line count (39 GB at 24,000 lines; above 46,340 it requires its parallel path, about 2 GB per worker), so a large basin is checked a watershed group at a time and never several at once: three at once coincided with each of three reboots of a 64 GB machine. And it rounds node coordinates to one decimal place fewer than `snap_tolerance` (10 m at its default of 0), so the tolerance has to be set (0.001 gives 1 cm).

## Not settled

- Watershed area on reattached side-channel segments: the watershed lookup gives a side channel its main river's area (#4).
- The paths' 1 m touch tolerance is right for flow (PCIC) and too loose for topology; the tree compensates with node tests rather than changing the shared paths.
