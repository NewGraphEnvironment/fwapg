# Walking downstream on the FWA: ltree, blue line path arrays, and a downstream_id

**Verified:** 2026-10-21 · **Issues:** NewGraphEnvironment/fwapg#34 (this measurement), #30 (the questions it answers), #2 (the main-flow tree the pointers come from), #3 (local codes out of order) · **Produced by:** `planning/archive/2026-10-issue-34-measure-downstream-queries/scripts/` (`bench.sh` and its SQL) on a full provincial fwapg (4,907,441 segments), one machine; logs in that directory's `logs/`

Three ways of answering "the segments downstream of a point, in order, to a distance or to the outlet":

| | reads | a walk is |
|---|---|---|
| **ltree** | `whse_basemapping.fwa_downstream()`, a predicate on watershed and local codes and measures; `fwa_downstreamtrace()` wraps it and reads `fwa_streams` | a join of the origin against every segment, through the GiST and btree code indexes |
| **arrays** | `fwapg.blk_paths` (one row per blue line: the lines its water passes through to the sea, and the junction measure on each), built by `extras/blue_line_paths` | the origin's line below the origin, then each line on its path below the junction: one index range per line on `(blue_line_key, downstream_route_measure)` |
| **`downstream_id`** | `fwapg.downstream_ids` (one row per segment: the next segment downstream and the length walked to reach its downstream end) | a recursive CTE, one primary-key lookup per step |

## What each returns

- **ltree returns the set the codes describe, not the water's path.** On the 4,000 comparison origins (1,000 random, 3,000 from three watershed groups) it returns about 1.4 times the segments of the walks (5.68 M rows against 4.00 M): 1.64 M of the extra rows are side channels, lines the water does not pass through. It cannot return the path alone (filtering to `blue_line_key = watershed_key` drops the braids the water does pass through), cannot bound a walk by distance, and orders by codes, which is not flow order where local codes run out of order along a line (#3's shape: 1,242 distinct segment pairs on the 4,000 origins' chains) or where two lines share both codes (the order is then decided by measure, which across two lines means nothing). It misses segments with a null local code (158,188 on the network, edge types 1450, 1100 and 1350 mostly) except on the origin's own line.
- **The shipped trace** (`fwa_downstreamtrace`) is the ltree predicate over `fwa_streams`, which lacks 369,217 segments (it keeps only segments with a watershed lookup row and an upstream-area row): on 100 origins it returned the predicate's set less 1,495 such segments, and nothing else differed. Its `ORDER BY` has no unique key, so tied lines come back in either order.
- **The array walk returns the chain of lines the water passes**, with a distance on every segment. It stops where the paths stop: at a line with no path (outlets, lines whose water leaves BC before reaching their parent, codes under 999), and it drops the one parent segment where a code junction is one segment below the tributary's mouth.
- **The pointer walk returns the same chain**, with the same distances. Built from the main-flow tree's node matches first, then the next segment on the line, then the path junction, it continues where the array walk stops at a pathless line whose mouth is on a tree node, and keeps the segment the code junction drops.
- **The array predicate** (`fwapg.blk_on_or_upstream()`) used as a join returns the array walk's set plus the segment that starts at each junction: it compares measures inclusively, and water joining at a segment's start does not pass that segment.

### Correctness, measured

On 4,000 origins (random 1..1,000 and a seeded 1,000 from each of ADMS, BULK and LFRA), every set, order and distance difference was attributed to a class by a SQL predicate, with none left over (`07_compare.sql`):

| pair | class | segments | origins |
|---|---|---|---|
| arrays vs pointers | the paths stop at a line with no path; the pointers go on | 3,077 | 4 |
| | code junction one segment below the mouth node | 17 | 17 |
| | tree and paths take different lines, then rejoin | 21 | 3 |
| ltree vs arrays | side channels | 1,640,569 | 3,837 |
| | the paths stop; the codes go on down the code ancestors | 31,430 | 29 |
| | main stem beside a side channel the water is in | 2,325 | 475 |
| | path through a braid the codes do not count | 1,919 | 702 |
| | local codes out of order or nested (#3) | 550 | 264 |
| | a code parent the path passes by (a touch further down) | 94 | 20 |
| | main stem below a side channel's rejoin, same local code | 91 | 25 |
| | null local code | 47 | 23 |
| | order: local codes out of order along a line | 43,320 | 3,688 |
| | order: two lines with the same codes | 53 | 45 |

The arrays and the pointers agree on 3,976 of the 4,000 origins, and where their sets agree the largest distance difference is 0 m: both sum the same per-segment step (`step_m`, below). From Hope (Fraser, measure 160400) both return 239 segments, 161.40 km of main flow, as `docs/03_functions.md` gives; ltree returns 544 segments, 309.70 km, against the docs' 308.54 km, which is stale.

## Building them

- **Arrays:** `extras/blue_line_paths` rebuilt in 992 s (16.5 min), 228 MB for `blk_paths` with its key (`blk_parents`, 136 MB, is read only by the build). The rebuild is deterministic: sorted-row md5s of both tables were identical before and after.
- **`downstream_id`:** 142 s, 385 MB with its key (heap 280 MB, key 105 MB), from the tree and the paths, so the paths' 992 s comes first. Every segment has a row: `node` (4,547,628: the tree segment whose upstream end is this segment's downstream end, nodes at 1 cm), `line` (136,786: the next segment on the line), `junction` (9,800: a line's lowest segment, onto the first line on its path with a segment below the junction), null (213,227 roots: 27,096 in the tree, being 26,690 outlets at BC's edge, 23 mouths with no parent inside BC and 383 dead ends whose every path line starts at the junction; and 186,131 off the tree, the lowest segments of lines with no path and of lines whose path has no segment below any junction). One walk up from the roots reaches every segment once, so the pointers form a forest. `step_m` is the target's length after a node or line step, and `junction − downstream_route_measure` of the target after a junction step (its length when the junction is within 1 cm of its top); the array walk computes the same expression.
- **ltree:** no build; its code indexes on `fwa_stream_networks_sp` are 1,923 MB (GiST and btree on both codes).

## Speed

Measured on one machine (16 cores, 128 GB, PostgreSQL 17.5 in Docker Desktop, `shared_buffers` 32 GB, `work_mem` 2 GB, warm cache), each walk consumed under one row of aggregates over every output column, so every row is computed and none is written. Medians of three repeats after a warm-up; "with / without" is server defaults (up to 8 workers) and `max_parallel_workers_per_gather = 0`. A statement with no origins costs about 1 ms (55 ms for the array predicate); a single origin is the median of 20.

To the outlet, random origins:

| origins | shipped trace | ltree join | array walk | pointer walk |
|---|---|---|---|---|
| 1 | 28 ms | 8 ms | 2.5 ms | 2.3 ms |
| 1,000 | 15 s / 29 s | 12 s / 7.6 s | 1.3 s / 1.3 s | 2.4 s / 1.7 s |
| 10,000 | | 102 s / 62 s | 9.2 s / 12 s | 6.1 s / 5.2 s |
| 100,000 | | 943 s / 607 s | 210 s / 348 s | 219 s / 196 s |

A random origin has about 1,160 segments below it on the walks (1,770 for ltree), so 100,000 origins are 115 M rows (174 M). Within 1 km (about 5 segments): the array walk 42 ms at 1,000 origins and 2.6 s at 100,000, the pointer walk 19 ms and 1.5 s. Every segment of a watershed group, to the outlet, with / without workers: ADMS (10,458) ltree 154 / 124 s, arrays 9.4 / 16 s, pointers 16 / 16 s; BULK (30,046) 199 / 216 s, 12 / 100 s, 47 / 49 s; LFRA (18,180) 101 / 137 s, 1.7 / 2.5 s, 2.7 / 3.0 s.

- **The two walks are within a factor of two of each other, except on BULK with workers**, where the array walk is 3.7 times faster. To the outlet the array walk leads at 1,000 origins and on every whole group with workers; the pointer walk leads at 10,000 origins, at 100,000 without workers, on ADMS and BULK without workers, and on every 1 km walk (about twice as fast). A recursive CTE never uses workers, so the pointer walk's two passes agree; the array walk's window sort uses them.
- **Both are 4 to 17 times faster than the ltree join** at 1,000 and 10,000 origins, and 1.7 to 4.5 times at 100,000, where both slow per origin (from about 1 ms to about 2 ms) and the join does not; that rise was not investigated.
- **Workers slow the ltree join** at every random batch; the shipped trace is the reverse.
- **The array predicate cannot be a join condition**: 15.5 s for one origin, because it is evaluated on every segment of the province, and 1,000 origins time out at 30 minutes.

## Answers to #30

**Paths against a `downstream_id` walked recursively.** Neither beats the other by much, and which leads depends on the walk: the arrays to the outlet at 1,000 origins and on whole watershed groups with workers (3.7 times on BULK), the pointers at 10,000 origins, at 1 km (about twice as fast) and on large batches without workers (up to twice as fast). On correctness the pointers are slightly ahead: they agree with the arrays on 3,976 of 4,000 origins, and of the other 24, the pointers keep the segment a code junction drops (17), continue where the paths stop but the mouth is on the tree (4) and take the tree's line where the paths take another before rejoining (3). They cost the paths' build plus 142 s and 385 MB, against the paths' 228 MB, and are the simpler query (no window over the rows). They do not win decisively, so the paths stay what the extras use; a `downstream_id` is cheap to add from the tree and paths if a consumer needs 1 km walks or single-core speed.

**The array query against ltree, and the `fwa_` functions.** The array walk is 4 to 10 times faster than the ltree join at 1,000 origins and returns a different thing: the water's path, ordered, with a distance on every segment, where ltree returns everything the codes put below the origin, side channels included, ordered by codes. Arrays are not the cost: the walk unnests about four junctions an origin and reads one index range per line. An `fwa_` function could use the paths as a walk (a set-returning function per origin, or a join over the unnested path), not by putting `fwapg.blk_on_or_upstream()` in a join's `ON` clause, which reads every segment for each origin. Because the sets differ, it would be a new function beside `FWA_Downstream()`, not a faster drop-in.
