# Walking downstream on the FWA: ltree, blue line path arrays, and a downstream_id

**Verified:** 2026-10-21 · **Issues:** NewGraphEnvironment/fwapg#34 (this measurement), #30 (the questions it answers), #2 (the main-flow tree the pointers come from), #3 (local codes out of order) · **Produced by:** `planning/archive/2026-10-issue-34-measure-downstream-queries/scripts/` (`bench.sh` and its SQL) on a full provincial fwapg (4,907,441 segments), one machine; logs in that directory's `logs/`

Three ways of answering "the segments downstream of a point, in order, to a distance or to the outlet":

| | reads | a walk is |
|---|---|---|
| **ltree** | `whse_basemapping.fwa_downstream()`, a predicate on watershed and local codes and measures; `fwa_downstreamtrace()` wraps it and reads `fwa_streams` | a join of the origin against every segment, through the GiST and btree code indexes |
| **arrays** | `fwapg.blk_paths` (one row per blue line: the lines its water passes through to the sea, and the junction measure on each), built by `extras/blue_line_paths` | the origin's line below the origin, then each line on its path below the junction: one index range per line on `(blue_line_key, downstream_route_measure)` |
| **`downstream_id`** | `fwapg.downstream_ids` (one row per segment: the next segment downstream and the length walked to reach its downstream end) | a recursive CTE, one primary-key lookup per step |

## What each returns

- **ltree returns the set the codes describe, not the water's path.** On the 4,000 comparison origins (1,000 random, 3,000 from three watershed groups) it returns about 1.4 times the segments of the walks (5.68 M rows against 4.00 M): 1.66 M of the extra rows are side channels, lines the water does not pass through. It cannot return the path alone (filtering to `blue_line_key = watershed_key` drops the braids the water does pass through), cannot bound a walk by distance, and orders by codes, which is not flow order where local codes run out of order along a line (#3's shape: 1,242 distinct segment pairs on the 4,000 origins' chains) or where two lines share both codes (the order is then decided by measure, which across two lines means nothing). It misses segments with a null local code (158,188 on the network, edge types 1450, 1100 and 1350 mostly) except on the origin's own line.
- **The shipped trace** (`fwa_downstreamtrace`) is the ltree predicate over `fwa_streams`, which lacks 369,217 segments (it keeps only segments with a watershed lookup row and an upstream-area row): on 100 origins it returned the predicate's set less 1,495 such segments, and nothing else differed. Its `ORDER BY` has no unique key, so tied lines come back in either order.
- **The array walk returns the chain of lines the water passes**, with a distance on every segment. It stops where the paths stop: at a line with no path (outlets, lines whose water leaves BC before reaching their parent, codes under 999), and it drops the one parent segment where a code junction is one segment below the tributary's mouth.
- **The pointer walk returns the same chain**, with the same distances. Built from the main-flow tree's node matches first, then the next segment on the line, then the path junction, it continues where the array walk stops at a pathless line whose mouth is on a tree node, and keeps the segment the code junction drops.
- **The array predicate** (`fwapg.blk_on_or_upstream()`) used as a join returns the array walk's set plus the segment that starts at each junction: it compares measures inclusively, and water joining at a segment's start does not pass that segment.

### Correctness, measured

On 4,000 origins (random 1..1,000 and a seeded 1,000 from each of ADMS, BULK and LFRA), every set, order and distance difference was attributed to a class by a SQL predicate, with none left over (`07_compare.sql`):

| pair | class | segments | origins |
|---|---|---|---|
| arrays vs pointers | pathless line, pointer goes on | 3,073 | 3 |
| | code junction one segment below the mouth node | 17 | 17 |
| | tree and paths take different lines | 25 | 4 |
| ltree vs arrays | side channels | 1,661,801 | 3,818 |
| | pathless line, codes go on | 10,292 | 26 |
| | main stem beside a side channel the water is in | 2,325 | 475 |
| | path through a braid the codes do not count | 1,919 | 702 |
| | local codes out of order or nested (#3) | 550 | 264 |
| | main stem below a side channel's rejoin, same local code | 91 | 25 |
| | null local code | 47 | 23 |
| | order: local codes out of order along a line | 43,320 | 3,688 |
| | order: two lines with the same codes | 53 | 45 |

The arrays and the pointers agree on 3,976 of the 4,000 origins, and where their sets agree they agree on every distance to the bit: both sum the same per-segment step (`step_m`, below). From Hope (Fraser, measure 160400) both return 239 segments, 161.40 km of main flow, as `docs/03_functions.md` gives; ltree returns 544 segments, 309.70 km, against the docs' 308.54 km, which is stale.

## Building them

- **Arrays:** `extras/blue_line_paths` rebuilt in 992 s (16.5 min), 228 MB for `blk_paths` with its key (`blk_parents`, 136 MB, is read only by the build). The rebuild is deterministic: sorted-row md5s of both tables were identical before and after.
- **`downstream_id`:** 142 s, 385 MB with its key (heap 280 MB, key 105 MB), from the tree and the paths, so the paths' 992 s comes first. Every segment has a row: `node` (4,547,628: the tree segment whose upstream end is this segment's downstream end, nodes at 1 cm), `line` (136,786: the next segment on the line), `junction` (9,800: a line's lowest segment, onto the first line on its path with a segment below the junction), null (213,227 roots: 27,096 in the tree, being 26,690 outlets at BC's edge, 23 mouths with no parent inside BC and 383 dead ends whose every path line starts at the junction; and 186,131 off the tree, the lowest segments of lines with no path and of lines whose path has no segment below any junction). One walk up from the roots reaches every segment once, so the pointers form a forest. `step_m` is the target's length after a node or line step, and `junction − downstream_route_measure` of the target after a junction step (its length when the junction is within 1 cm of its top); the array walk computes the same expression.
- **ltree:** no build; its code indexes on `fwa_stream_networks_sp` are 1,923 MB (GiST and btree on both codes).

## Speed

*(timings pending)*

## Answers to #30

*(pending the timings)*
