# Walking downstream on the FWA: the options, how they score, and what is open

**Verified:** 2026-10-22 · **Issues:** NewGraphEnvironment/fwapg#34 (this measurement), #30 (the questions it answers), #2 (the main-flow tree), #3 (local codes out of order) · **Produced by:** `planning/archive/2026-10-issue-34-measure-downstream-queries/scripts/` (`bench.sh` and its SQL) on a full provincial fwapg (4,907,441 segments), one machine; logs in that directory's `logs/`; the province-wide defect counts are queries run 2026-10-22 against the same database

The question: from a point on the network, which segments are downstream, in order, and how far, to a distance or to the outlet. Fresh, wet and link all need it.

This is a working guide from one round of measurement. It will have mistakes, and where it suggests a fix or a decision belongs is a starting point to talk through, not a rule.

## In short

- **Two of the five options follow the water:** the path walk and the `downstream_id` walk. The other three answer from watershed codes, a broader set in a different order.
- **On accuracy the `downstream_id` walk leads.** The path walk gives a different answer on 21 of 4,000 sampled origins (0.5 %), from two defects in the path tables (Known defects 1 and 2). No error of the `downstream_id` walk was found; 3 origins take a different braid and are undecided.
- **On speed the two walks trade places,** within about 4 times of each other, and both are 3 to 58 times faster than the ltree join. Within 1 km the `downstream_id` walk is 1.7 to 5.5 times faster.
- **The `downstream_id` table is a prototype:** built once in a local database by the archived benchmark script, on no branch.
- **Open decision:** which walk fresh, wet and link use by default (Open questions 1).

## The options

| # | option | where it lives | built from | how a walk works | returns |
|---|---|---|---|---|---|
| 1 | **ltree join**: `FWA_Downstream()` as a join condition | fwapg, function | nothing (code indexes on `fwa_stream_networks_sp`) | compares the origin's codes and measure with every segment's, through the GiST and btree code indexes | every segment the codes put below the origin, side channels included, in code order |
| 2 | **shipped trace**: `FWA_DownstreamTrace()` | fwapg, function | reads `fwa_streams` | option 1 over `fwa_streams`, with every column and geometry, the origin's segment cut at the measure | as option 1, less the 369,217 segments `fwa_streams` lacks |
| 3 | **path walk** over `fwapg.blk_paths` | tables from `extras/blue_line_paths` on the `newgraph` branch; the walk is a query in the benchmark scripts | each line's parent and junction (codes, then touching mouths, then fallbacks), chained to the sea | the origin's line below the origin, then each line on its path below its junction: one index range per line (about 4 a random origin), then a sort for order and distance | the lines the water passes, in flow order, with a distance to every segment |
| 4 | **path predicate**: `fwapg.blk_on_or_upstream()` as a join condition | `extras/blue_line_paths` on the `newgraph` branch, function | `blk_paths` | evaluated against every segment of the province for each origin | option 3's set plus the segment starting at each junction |
| 5 | **`downstream_id` walk** over `fwapg.downstream_ids` | prototype, on no branch (`01_downstream_ids.sql` in the archive) | per segment: the main-flow tree segment at its downstream node; else the next segment on its line; else, for a line's lowest segment, the path junction | a recursive query: look up the next segment, add its length, repeat (about 1,160 steps from a random origin to the sea, 5 within 1 km) | the same chain as option 3, segment by segment along the geometry |

How they depend on each other:

```
FWA network (fwa_stream_networks_sp) ── watershed and local codes ──> options 1, 2 (fwapg)
        │
        └─> extras/blue_line_paths, newgraph branch: blk_parents, blk_paths (16.5 min, 228 MB) ──> options 3, 4; PCIC crosswalk
                    │
                    └─> extras/mainflow_tree, newgraph branch: the main-flow tree (#2, 482 MB; it rebuilds the paths first)
                                │
                                └─> downstream_ids, prototype (142 s, 385 MB; reads the tree and the paths) ──> option 5
```

A change to the paths reaches options 3, 4 and 5, the PCIC crosswalk and the tree; a change to the tree reaches option 5.

## Scorecard

Accuracy is scored against the water's path along the segment geometry, on 4,000 origins (1,000 random and 1,000 from each of ADMS, BULK and LFRA), with every difference attributed (Detail, Correctness). Speed is at server defaults on one machine (Detail, Speed).

| | 1 ltree join | 2 shipped trace | 3 path walk | 4 path predicate | 5 `downstream_id` walk |
|---|---|---|---|---|---|
| **follows the water** | no: the code set, about 1.4 times the segments, mostly side channels | no, as 1 | yes | yes, plus one segment at each junction | yes |
| **known differences** | code order is not flow order where local codes run out of order (1,208 segment pairs on the sample's chains) or two lines share both codes; segments with a null local code (158,188 outside the codes under 999) appear only on the origin's own line; continues down code ancestors where the water leaves BC | as 1, and lacks segments absent from `fwa_streams` (1,495 on 100 origins, the only difference in the set) | 21 of 4,000 origins: one segment dropped (17), walk stops early (4) | as 3 | none found; 3 origins take a different braid, undecided |
| **notes** | filtering to main flow does not give the path: it also drops braids the water passes through | its sort has no unique key, so lines that tie come back in either order | | compares measures inclusively, so it counts the segment that starts at a junction | inherits the main-flow tree's choices |
| **1 origin** | 8 ms | 28 ms | 2.5 ms | 15.5 s | 2.3 ms |
| **1,000 origins, to the outlet** | 12 s | 15 s | 1.3 s | over 30 min | 2.4 s |
| **100,000 origins, to the outlet** | 943 s (one run) | | 210 s | | 219 s |
| **1,000 origins, 1 km** | no distance bound | no distance bound | 42 ms | no distance bound | 19 ms |
| **parallel workers** | slow it 1.15 to 1.6 times | speed it 2 times | speed it 1.5 to 7.6 times | | none used |
| **build** | none (code indexes 1.9 GB) | none | 16.5 min, 228 MB | the paths | the paths and the tree, then 142 s, 385 MB |
| **ships** | fwapg | fwapg | `newgraph` branch (tables) | `newgraph` branch | nowhere yet |

## Known defects and where they are fixed

One row per defect found so far. "Layer" says where a fix most likely belongs; "fixed by" links to the fix, or to where it is offered or tracked.

| # | defect | effect | layer | count | fixed by | status |
|---|---|---|---|---|---|---|
| 1 | A parent segment carries the tributary's own local code one segment below the tributary's mouth, so the path junction sits one segment low | the path walk, the path predicate and the PCIC crosswalk drop that segment; 14 of the 1,000 random origins drain through one of these lines | FWA source data (local codes) | 3 lines: MSKE (Skeena, 72 m), LFRA (152 m), LFRA (1.5 m) | a code correction, offered on [#30](https://github.com/NewGraphEnvironment/fwapg/issues/30); on the `newgraph` branch, Open questions 2 and 9 | offered |
| 2 | A line has no path although the water continues past its mouth | walks on the paths stop at its mouth: in the sample, two ADMS origins lost 550 km to the sea, an LFRA origin 58 km, a GRAI origin 0.6 km | not known until diagnosed: the path rules or the source data | 196 lines (83 in the main-flow tree) | Open questions 3 | open |
| 3 | Local codes out of order, or nested more than one level (#3's shape) | the ltree join returns a set or order that does not follow the water | FWA source data | 2,013 candidate main-flow segments, found by query, not checked one by one | code corrections, offered on [#30](https://github.com/NewGraphEnvironment/fwapg/issues/30) | offered |
| 4 | Beaver River: one watershed code with two main lines, whose 6010 connectors leave one node (a split) | the main-flow tree | FWA source data | 1 segment (868144443) | [`extras/mainflow_tree/overrides.csv`](../extras/mainflow_tree/overrides.csv) on the `newgraph` branch | fixed on the `newgraph` branch |
| 5 | The Hope total in the docs: 308.54 km given, 309.70 km returned | `docs/03_functions.md` | upstream docs | 1 figure | a docs PR, offered on #30 | offered |

A rough guide to where things tend to belong, to revise as cases teach us otherwise: a measured fact goes in this file; a correction to FWA data is offered upstream, where the maintainer decides; a decision about one feature is an override row on the `newgraph` branch; a behaviour that should hold generally is a rule in that build's SQL.

## Other risks

- **The `downstream_id` walk inherits the main-flow tree's choices.** Where the tree has a gap (473 dead ends, 8 cut-offs, 23 mouths with no parent inside BC, one override), its pointer falls back to the line and the path junction, so a path defect can reach it there.
- **The `downstream_id` table has no build job, QA in a job, load file or published output,** and has to be rebuilt after the paths and the tree, in that order, or it walks the old network.
- **The measurement is one machine** (Docker Desktop on macOS, the database on a host mount, warm cache). Absolute times may differ on a Linux host. The ltree join's 100,000-origin and whole-group cells are single runs.

## Open questions and follow-ups

| # | question or task | why it matters | how it gets settled | where the answer would likely live | status |
|---|---|---|---|---|---|
| 1 | Which walk do fresh, wet and link use by default? | accuracy against speed | a decision: the `downstream_id` walk leads on accuracy; the two trade places on speed | this file, as a dated decision with its reasons, and the issue that lands it | **open, needs a decision** |
| 2 | Correct the local codes behind Known defects 1 | three lines drop a segment on every path-based walk through them | the maintainer's call on the offered correction; on the `newgraph` branch meanwhile, see 9 | upstream, in the maintainer's fixes file; on the `newgraph` branch, a path-build override row or a change to `blue_line_paths.sql` | offered |
| 3 | Why do 196 lines have no path although the water continues? (Known defects 2) | walks on the paths stop early | sort the 196 by why `blue_line_paths.sql` gave no parent (no code parent in BC, a gap in the touch rules, codes under 999 nearby) | `blue_line_paths.sql` if a rule misses them; upstream if the codes are the cause; this file if the behaviour is right (water leaving BC, for example) | open |
| 4 | Which braid should a walk follow for the 3 origins that differ? | where a river braids, water takes both channels and a single chain has to pick one, so this is partly a convention | look at the 3 against imagery and the geometry: a dry or artefact channel is a correction; two live channels call for a stated convention | an override row in the build that made the choice; or a convention in this file and the tree's README; or a rule change if many cases share the cause | open |
| 5 | Land `downstream_ids` as an extra | needed if 1 chooses it | build script, QA, load file, output under `fwapg/extras/`, rebuilt after the paths and the tree | a new extra on the `newgraph` branch | waits on 1 |
| 6 | Why do both walks slow per origin at 100,000 origins? | province-wide runs | EXPLAIN at 100,000 for a sort or tuplestore spilling past `work_mem` | this file, Speed | open |
| 7 | Re-time the headline cells on the production host | the times here come from a Docker Desktop mount | re-run the `bench.sh` cells there | this file, Speed | open |
| 8 | Offered upstream: Known defects 1, 3 and 5, and a `downstream_id` table if useful in fwapg | the maintainer's package | his reply on #30 | the maintainer's repo, if he wants them | offered |
| 9 | While a source-data fix waits upstream: a general rule in the `newgraph` build, or a per-feature override file (as `extras/mainflow_tree/overrides.csv`)? | a rule fixes every matching case but changes the build for all; an override is explicit and retires when the source is corrected | decided when a fix is taken up | the "fixed by" column of each defect, case by case | open |

## Detail

### Correctness

On 4,000 origins (random 1..1,000 and a seeded 1,000 from each of ADMS, BULK and LFRA), every set, order and distance difference was attributed to a class by a SQL predicate, with none left over (`07_compare.sql`):

| pair | class | segments | origins |
|---|---|---|---|
| path walk vs `downstream_id` walk | the paths stop at a line with no path; the `downstream_id` walk goes on | 3,077 | 4 |
| | code junction one segment below the mouth node | 17 | 17 |
| | tree and paths take different lines, then rejoin | 21 | 3 |
| ltree join vs path walk | side channels | 1,652,256 | 3,843 |
| | the paths stop; the codes go on down the code ancestors' main lines | 19,743 | 15 |
| | main stem beside a side channel the water is in | 2,325 | 475 |
| | path through a braid the codes do not count | 1,919 | 702 |
| | local codes out of order or nested (#3) | 550 | 264 |
| | a code parent the path passes by (a touch further down) | 94 | 20 |
| | main stem below a side channel's rejoin, same local code | 91 | 25 |
| | null local code | 47 | 23 |
| | order: local codes out of order along a line | 43,320 | 3,688 |
| | order: two lines with the same codes | 53 | 45 |
| | order: across a braid on the path | 9 | 9 |

Where the two walks return the same set, their distances agree to 0 m: both sum the same per-segment step (`step_m`, below). From Hope (Fraser, measure 160400) both return 239 segments, 161.40 km of main flow, as `docs/03_functions.md` gives; the ltree join returns 544 segments, 309.70 km.

### Building them

- **Paths:** `extras/blue_line_paths` rebuilt in 992 s (16.5 min); `blk_paths` is 228 MB with its key, and `blk_parents` (136 MB) is read by the path and tree builds, not by the walk. The rebuild is deterministic: sorted-row md5s of both tables were identical before and after.
- **`downstream_ids`:** 142 s, 385 MB with its key (heap 280 MB, key 105 MB), once the paths and the main-flow tree exist (#2, 482 MB, built by `extras/mainflow_tree`, which rebuilds the paths itself). Every segment has a row: `node` 4,547,628 (the tree segment whose upstream end is this segment's downstream end, nodes at 1 cm), `line` 136,786 (the next segment on the line), `junction` 9,800 (a line's lowest segment, onto the first line on its path with a segment below the junction), and null 213,227. The nulls are 27,096 in the tree (26,690 outlets at BC's edge, 23 mouths with no parent inside BC, 383 dead ends whose every path line starts at the junction) and 186,131 off it (the lowest segments of lines with no path, or whose path has no segment below any junction). One walk up from the roots reaches every segment once, so the pointers form a forest. `step_m` is the target's length after a node or line step, and `junction − downstream_route_measure` of the target after a junction step (its length when the junction is within 1 cm of its top); the path walk uses the same expression.
- **ltree:** no build; its code indexes on `fwa_stream_networks_sp` are 1,923 MB.

### Speed

One machine (16 cores, 128 GB, PostgreSQL 17.5 in Docker Desktop, `shared_buffers` 32 GB, `work_mem` 2 GB, warm cache). Each walk ran under one row of aggregates over every output column, so every row is computed and none is written. Times are at server defaults (up to 8 workers), medians of three repeats after a warm-up; a single origin is the median of 20 origins; the ltree join's 100,000-origin and whole-group cells are one run each, with no warm-up. A statement with no origins costs 0.8 to 1.6 ms (55 ms for the path predicate).

To the outlet, random origins:

| origins | shipped trace | ltree join | path walk | `downstream_id` walk |
|---|---|---|---|---|
| 1 | 28 ms | 8 ms | 2.5 ms | 2.3 ms |
| 1,000 | 15 s | 12 s | 1.3 s | 2.4 s |
| 10,000 | | 102 s | 9.2 s | 6.1 s |
| 100,000 | | 943 s (one run) | 210 s | 219 s |

A random origin has about 1,160 segments below it on the walks (1,770 on the ltree join), so 100,000 origins are 115 M rows (174 M). Within 1 km, about 5 segments an origin, the path walk takes 42 ms at 1,000 origins and 2.6 s at 100,000, the `downstream_id` walk 19 ms and 1.5 s. Every segment of a watershed group, to the outlet (ltree join, path walk, `downstream_id` walk): ADMS (10,458 origins) 154 s, 9.4 s, 16 s; BULK (30,046) 199 s, 12 s, 47 s; LFRA (18,180) 101 s, 1.7 s, 2.7 s.

The path walk's time over the `downstream_id` walk's, to the outlet (below 1, the path walk is faster):

| batch | path / `downstream_id` |
|---|---|
| 1 random origin | 1.07 |
| random 1,000; 10,000; 100,000 | 0.53; 1.50; 0.96 |
| 1,000 from ADMS; BULK; LFRA | 1.22; 1.25; 2.13 |
| all of ADMS; BULK; LFRA | 0.59; 0.27; 0.66 |

- **To the outlet, neither walk leads everywhere:** the path walk is faster on random 1,000 and the three whole groups (up to 3.8 times, BULK), the `downstream_id` walk on random 10,000 and the three groups' 1,000-origin samples (up to 2.1 times, LFRA).
- **Within 1 km the `downstream_id` walk is 1.7 to 5.5 times faster** on each batch measured, with and without workers.
- **Against the ltree join, to the outlet:** the path walk is 3.3 times faster at one origin and 4.5 to 58 times on batches; the `downstream_id` walk 3.5 times and 4.3 to 47 times (at random 1,000: 9.7 and 5.2 times).
- **Workers,** from 11 cells re-run at both settings interleaved, with the `downstream_id` walk (which uses none, and moved 0.90 to 1.01 between settings) as the control for drift: they speed the path walk 1.5 times (random 1,000), 1.7 times (random 10,000) and 7.6 times (BULK, which without them takes 101 s against the `downstream_id` walk's 52 s); speed the shipped trace 2 times (random 1,000); slow the ltree join 1.6 times (random 1,000) and 1.15 times (random 10,000); and leave the 1 km walks unchanged. At one origin both settings give the same times for every method. Other cells were not interleaved, and their no-worker times mix the setting with drift between runs.
- **Per origin, both walks slow from 10,000 to 100,000 origins** (the path walk from 0.9 to 2.1 ms, the `downstream_id` walk from 0.6 to 2.2 ms) while the ltree join holds at 9 to 10 ms; not yet investigated (Open questions 6).
- **The path predicate is a poor fit as a join condition:** 15.5 s for one origin, because it is evaluated on every segment of the province, and 1,000 origins time out at 30 minutes.

## Answers to #30

**2. Paths compared with a `downstream_id` walked recursively.** Neither is ahead on both counts. On speed the two trade places (Scorecard). On accuracy the `downstream_id` walk is ahead: the two differ on 24 of 4,000 origins, and in 21 of those the difference comes from the path tables (Known defects 1 and 2). Given the main-flow tree, the table costs 142 s and 385 MB on top of the paths.

**3. Arrays compared with ltree.** The arrays are cheap: a walk unnests about four junctions an origin, reads one index range per line, and runs 5 to 12 times faster than the `FWA_Downstream()` join at 1,000 origins, though the two return different sets. The path predicate `blk_on_or_upstream()` is a poor fit as a join condition; a walk is the way to use the paths.
