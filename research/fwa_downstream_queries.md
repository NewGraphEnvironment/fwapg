# Walking downstream on the FWA: the options, how they score, and what is open

**Verified:** 2026-10-22 · **Issues:** NewGraphEnvironment/fwapg#34 (this measurement), #30 (the questions it answers), #2 (the main-flow tree), #3 (local codes out of order) · **Produced by:** `planning/archive/2026-10-issue-34-measure-downstream-queries/scripts/` (`bench.sh` and its SQL) on a full provincial fwapg (4,907,441 segments), one machine; logs in that directory's `logs/`; the province-wide defect counts in "Risks" are queries run 2026-10-22 against the same database

The question: from a point on the network, which segments are downstream, in order, how far, to a distance or to the outlet. Fresh, wet and link all need it.

This is a working guide, built from one round of measurement. It will have mistakes, and the homes it suggests for fixes and decisions are a starting point to talk through, not rules.

## In short

- **Two of the five options follow the water** (the path walk and the `downstream_id` walk); the other three answer from watershed codes, which is a broader and differently ordered set.
- **On accuracy the `downstream_id` walk leads.** The path walk gives a different answer on 21 of 4,000 sampled origins (0.5 %): a dropped segment at 3 junctions province-wide, and walks that stop early where 196 lines have no path although the water continues, losing up to 550 km. No error of the `downstream_id` walk was found; 3 origins route differently and are undecided.
- **On speed the two walks trade places** within about 4 times of each other, and both are 3 to 58 times faster than the ltree join. Within 1 km the `downstream_id` walk is 1.7 to 5.5 times faster.
- **The `downstream_id` table is a prototype:** it exists only in the local database, built by the archived benchmark script. Nothing ships it.
- **Decision open:** which walk is the default for fresh, wet and link (below, "Open questions" 1).

## The options

| # | option | whose, where it lives | built from | how a walk works | returns |
|---|---|---|---|---|---|
| 1 | **ltree join**: `FWA_Downstream()` as a join condition | fwapg (upstream), function | nothing; code indexes on `fwa_stream_networks_sp` | compares the origin's watershed and local codes and measure with every segment's, through the GiST and btree code indexes | every segment the codes put below the origin, side channels included, ordered by codes |
| 2 | **shipped trace**: `FWA_DownstreamTrace()` | fwapg (upstream), function | nothing; reads `fwa_streams` | option 1 over `fwa_streams`, every column with geometry, the origin's segment cut at the measure | as option 1, less the 369,217 segments `fwa_streams` lacks |
| 3 | **path walk** over `fwapg.blk_paths` | `extras/blue_line_paths` on the `newgraph` branch (tables); the walk is a query in the benchmark scripts, not a function | each line's parent and junction (codes, then touching mouths, then fallbacks), chained to the sea | the origin's line below the origin, then each line on its path below its junction: one index range per line (about 4 a random origin), then a sort for order and distance | the lines the water passes, in flow order, distance on every segment; stops where the paths stop |
| 4 | **path predicate**: `fwapg.blk_on_or_upstream()` as a join condition | `extras/blue_line_paths` on the `newgraph` branch, function | `blk_paths` | evaluated against every segment of the province for each origin | option 3's set plus the segment starting at each junction (inclusive comparison) |
| 5 | **`downstream_id` walk** over `fwapg.downstream_ids` | a prototype on no branch: built once in a local database by `01_downstream_ids.sql` in the archive | for each segment: the main-flow tree segment at its downstream node; else the next segment on its line; else, for a line's lowest segment, the path junction | a recursive query: look up the next segment, add its length, repeat (about 1,160 steps from a random origin to the sea, 5 within 1 km) | the same chain as option 3, segment by segment along the geometry |

How the pieces depend on each other:

```
FWA network (fwa_stream_networks_sp) ── watershed and local codes ──> options 1, 2 (fwapg)
        │
        └─> extras/blue_line_paths, newgraph branch: blk_parents, blk_paths (16.5 min, 228 MB) ──> options 3, 4; PCIC crosswalk
                    │
                    └─> extras/mainflow_tree, newgraph branch: the main-flow tree (#2, 482 MB; it rebuilds the paths first)
                                │
                                └─> downstream_ids, prototype (142 s, 385 MB; reads the tree and the paths) ──> option 5
```

A change to the paths therefore reaches options 3, 4 and 5, the PCIC crosswalk and the tree; a change to the tree reaches option 5.

## Scorecard

Accuracy is scored against the water's path along the segment geometry, on 4,000 origins (1,000 random, 1,000 from each of ADMS, BULK and LFRA), with every difference attributed (detail below). Speed is at server defaults on one machine (detail below).

| | 1 ltree join | 2 shipped trace | 3 path walk | 4 path predicate | 5 `downstream_id` walk |
|---|---|---|---|---|---|
| **follows the water** | no: the code set, 1.4 times the segments (side channels) | no: as 1 | yes | yes, plus one segment at each junction | yes |
| **known errors** | misorders where local codes run out of order (1,208 segment pairs on the sample's chains); misses null-local-code segments off the origin's line; counts code ancestors past where the water leaves BC | as 1, and lacks segments absent from `fwa_streams` | differs on 21 origins of 4,000: one segment dropped (17), walk stops early (4) | as 3 | none found; 3 origins route differently from 3, undecided |
| **1 origin** | 8 ms | 28 ms | 2.5 ms | 15.5 s | 2.3 ms |
| **1,000 origins, to the outlet** | 12 s | 15 s | 1.3 s | over 30 min | 2.4 s |
| **100,000 origins, to the outlet** | 943 s (one run) | | 210 s | | 219 s |
| **1,000 origins, 1 km** | no distance bound | no distance bound | 42 ms | no distance bound | 19 ms |
| **parallel workers** | slow it 1.15 to 1.6 times | speed it 2 times | speed it 1.5 to 7.6 times | | none used |
| **build** | none (code indexes 1.9 GB) | none | 16.5 min, 228 MB | the paths | paths, tree, then 142 s, 385 MB |
| **ships** | fwapg | fwapg | `newgraph` branch extra (tables only) | `newgraph` branch | nowhere yet |

## Risks

**Path walk (3), and so option 4, the PCIC crosswalk and the tree, which read the same paths:**

- **A code junction one segment below the tributary's mouth.** On 3 lines province-wide the path junction (from the codes) is the start of the parent segment whose top is where the tributary's mouth touches; the walk drops that segment (72 m and 1.5 m on the two met in the sample). Rare, but it sits on large systems: 14 of the 1,000 random origins drain through one of the 3, on a Skeena tributary.
- **Walks that stop where the water continues.** 196 lines with codes outside 999 have no path although their lowest segment connects by node to another segment (83 of them in the main-flow tree). A walk from anything above them ends at their mouth: in the sample, two ADMS origins lost 1,495 segments (550 km) to the sea, an LFRA origin 83 (58 km), a GRAI origin 4 (0.6 km). Not investigated: why these lines have no path.

**`downstream_id` walk (5):**

- **It inherits the main-flow tree's choices.** Where the tree has a gap (473 dead ends, 8 cut-offs, 23 mouths with no parent inside BC, one hand-set override) the pointer falls back to the line and the path junction, so a path defect can still reach it there (`Building them`, below).
- **It is a prototype.** No build job, load file, QA in a job or published output; the table in the local database was made once by the archived script.
- **Rebuild order:** paths, then tree, then the table; a stale table after a paths or tree rebuild would walk the old network.

**ltree (1, 2):** known and upstream: the code set is not the water's path (side channels, out-of-order local codes as in #3, null local codes, ancestors past where water leaves BC); the trace also reads `fwa_streams`, which lacks 369,217 segments, and orders with no unique key.

**The measurement itself:** one machine (Docker Desktop on macOS, the database on a host mount), warm cache; absolute times may differ on a Linux host. Both walks slow per origin from 10,000 to 100,000 origins (about 1 to 2 ms an origin), not investigated. The ltree join's 100,000 and whole-group cells are single runs.

## Known defects and where they are fixed

One row per defect found so far. "Layer" says where a fix belongs; "fixed by" links to the fix, or to where it is offered or tracked.

| # | defect | where it shows | layer | count | fixed by | status |
|---|---|---|---|---|---|---|
| 1 | A parent segment carries the tributary's own local code one segment below the tributary's mouth | the path walk drops that segment; so do the path predicate and the PCIC crosswalk | FWA source data (local codes) | 3 lines: MSKE (Skeena, 72 m), LFRA (152 m), LFRA (1.5 m) | a code correction at the source, offered on [#30](https://github.com/NewGraphEnvironment/fwapg/issues/30); on the `newgraph` branch, Open questions 2 and 9 | offered |
| 2 | A line has no path although the water continues past its mouth | path-based walks stop early (up to 550 km in the sample) | not known until diagnosed: the path rules or the source data | 196 lines (83 in the main-flow tree) | Open questions 3 | open |
| 3 | Local codes out of order, or nested more than one level (#3's shape) | the ltree join returns a set or order that does not follow the water | FWA source data | 2,013 candidate main-flow segments, found by query, not checked one by one | code corrections at the source, offered on [#30](https://github.com/NewGraphEnvironment/fwapg/issues/30) | offered |
| 4 | Beaver River: one watershed code with two main lines, whose 6010 connectors leave one node (a split) | the main-flow tree | FWA source data | 1 segment (868144443) | [`extras/mainflow_tree/overrides.csv`](../extras/mainflow_tree/overrides.csv) on the `newgraph` branch | fixed on the `newgraph` branch |
| 5 | The Hope total in the docs is stale: 308.54 km given, 309.70 km returned | `docs/03_functions.md` | upstream docs | 1 figure | a docs PR, offered on #30 | offered |

A rough guide to where things tend to belong, to be revised as cases teach us otherwise: a measured fact goes in this file; a correction to FWA data is offered upstream, where the maintainer decides; a decision about one feature is an override row on the `newgraph` branch; a behaviour that should hold generally is a rule in that build's SQL.

## Open questions and follow-ups

| # | question or task | why it matters | how it gets settled | where the answer would likely live | status |
|---|---|---|---|---|---|
| 1 | Which walk is the default for fresh, wet and link? | accuracy against speed | a decision: the `downstream_id` walk leads on accuracy, the two trade places on speed | the research doc, as a dated decision with its reasons, and the issue that lands it | **open, needs a decision** |
| 2 | Correct the local codes that put a code junction one segment below the mouth (3 lines; Known defects, row 1) | the path walk, the path predicate and the PCIC crosswalk drop a segment there | a code correction at the source, offered upstream on #30; on the `newgraph` branch meanwhile, a rule or a per-line override in the path build (question 9) | upstream, in the maintainer's fixes file if he takes the correction; on the `newgraph` branch meanwhile, a path-build override row or a change to `blue_line_paths.sql` | offered upstream |
| 3 | Why do 196 lines have no path although the water continues? | path-based walks stop early (up to 550 km lost in the sample) | list the 196 by why `blue_line_paths.sql` gave no parent (no code parent in BC, a gap in the touch rules, codes under 999 nearby); fix the paths or accept and document | depends on the diagnosis: `blue_line_paths.sql` if a rule misses these lines; upstream if the codes are the cause; the research doc if the behaviour is right (water leaving BC, for example) | open |
| 4 | Which braid should a walk follow for the 3 origins that route differently? | where a river braids, water takes both channels and a single chain has to pick one, so this is partly a convention | look at the 3 against imagery and the geometry: a dry or artefact channel is a correction; two live channels call for a stated convention | an override row in the build that made the choice (`extras/mainflow_tree/overrides.csv`, or a path-build override); a convention stated in the research doc and the tree's README if both channels carry water; or a rule change if many cases share the cause | open |
| 5 | Land `downstream_ids` as an extra on the `newgraph` branch | needed if 1 chooses it | build script, QA in the job, load file, published output under `fwapg/extras/`, rebuild order after paths and tree | a new extra on the `newgraph` branch: build script, QA, load file, output under `fwapg/extras/` | waits on 1 |
| 6 | Why both walks slow per origin at 100,000 origins | province-wide runs | EXPLAIN at 100,000 for a sort or tuplestore spilling past `work_mem` | the research doc, Speed section | open |
| 7 | Re-time the headline cells on the production host | absolute times here are a Docker Desktop mount | re-run `bench.sh` cells there | the research doc, Speed section, as a second machine | open |
| 8 | Offered upstream, the maintainer's call: the stale Hope figure in `docs/03_functions.md`; local-code corrections like #3 in the fixes file; a `downstream_id` table if useful in fwapg | his package | his reply on #30 | the maintainer's repo, if he wants them | offered |
| 9 | On the `newgraph` branch, while a source-data defect waits for a correction upstream: a general rule in the build, or a per-feature override file (as `extras/mainflow_tree/overrides.csv`)? | a rule fixes every matching case but changes the build for all; an override is explicit and retires when the source is corrected | decided when a fix is taken up | the "fixed by" column of each defect row, decided case by case | open |

## Detail

### What each returns

- **ltree returns the set the codes describe, not the water's path.** On the 4,000 comparison origins (1,000 random, 3,000 from three watershed groups) it returns about 1.4 times the segments of the walks (5.68 M rows against 4.00 M): 1.65 M of the extra rows are side channels, lines the water does not pass through. It cannot return the path alone (filtering to `blue_line_key = watershed_key` drops the braids the water does pass through), cannot bound a walk by distance, and orders by codes, which is not flow order where local codes run out of order along a line (#3's shape: 1,208 distinct segment pairs on the 4,000 origins' chains) or where two lines share both codes (the order is then decided by measure, which across two lines means nothing). It misses segments with a null local code (158,188 on the network outside the codes under 999, edge types 1450, 1100 and 1350 mostly) except on the origin's own line.
- **The shipped trace** (`fwa_downstreamtrace`) is the ltree predicate over `fwa_streams`, which lacks 369,217 segments (it keeps only segments with a watershed lookup row and an upstream-area row): on 100 origins it returned the predicate's set less 1,495 such segments, and nothing else in the set differed. Its `ORDER BY` has no unique key, so tied lines come back in either order.
- **The path walk returns the chain of lines the water passes**, with a distance on every segment. It stops where the paths stop: at a line with no path (outlets, lines whose water leaves BC before reaching their parent, codes under 999), and it drops the one parent segment where a code junction is one segment below the tributary's mouth.
- **The `downstream_id` walk returns the same chain**, with the same distances. Built from the main-flow tree's node matches first, then the next segment on the line, then the path junction, it continues where the path walk stops at a pathless line whose mouth is on a tree node, and keeps the segment the code junction drops.
- **The array predicate** (`fwapg.blk_on_or_upstream()`) used as a join returns the path walk's set plus the segment that starts at each junction: it compares measures inclusively, and water joining at a segment's start does not pass that segment.

#### Correctness, measured

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

The path walk and the `downstream_id` walk agree on 3,976 of the 4,000 origins, and where their sets agree the largest distance difference is 0 m: both sum the same per-segment step (`step_m`, below). From Hope (Fraser, measure 160400) both return 239 segments, 161.40 km of main flow, as `docs/03_functions.md` gives; ltree returns 544 segments, 309.70 km, against the docs' 308.54 km, which is stale.

### Building them

- **Arrays:** `extras/blue_line_paths` rebuilt in 992 s (16.5 min), 228 MB for `blk_paths` with its key (`blk_parents`, 136 MB, is read by the build and by the main-flow tree build, not by the walk). The rebuild is deterministic: sorted-row md5s of both tables were identical before and after.
- **`downstream_id`:** 142 s, 385 MB with its key (heap 280 MB, key 105 MB), from the tree and the paths, so both come first: the paths' 992 s, and the main-flow tree (#2, 482 MB, built by `extras/mainflow_tree`, which rebuilds the paths itself); this measurement took the tree as already built. Every segment has a row: `node` (4,547,628: the tree segment whose upstream end is this segment's downstream end, nodes at 1 cm), `line` (136,786: the next segment on the line), `junction` (9,800: a line's lowest segment, onto the first line on its path with a segment below the junction), null (213,227 roots: 27,096 in the tree, being 26,690 outlets at BC's edge, 23 mouths with no parent inside BC and 383 dead ends whose every path line starts at the junction; and 186,131 off the tree, the lowest segments of lines with no path and of lines whose path has no segment below any junction). One walk up from the roots reaches every segment once, so the pointers form a forest. `step_m` is the target's length after a node or line step, and `junction − downstream_route_measure` of the target after a junction step (its length when the junction is within 1 cm of its top); the path walk computes the same expression.
- **ltree:** no build; its code indexes on `fwa_stream_networks_sp` are 1,923 MB (GiST and btree on both codes).

### Speed

Measured on one machine (16 cores, 128 GB, PostgreSQL 17.5 in Docker Desktop, `shared_buffers` 32 GB, `work_mem` 2 GB, warm cache), each walk consumed under one row of aggregates over every output column, so every row is computed and none is written. Unless a line says otherwise, the times are at server defaults (up to 8 workers), medians of three repeats after a warm-up; a single origin is the median of 20 origins; the ltree join's 100,000-origin and whole-group cells are one run each, with no warm-up. A statement with no origins costs 0.8 to 1.6 ms (55 ms for the path predicate).

To the outlet, random origins:

| origins | shipped trace | ltree join | path walk | `downstream_id` walk |
|---|---|---|---|---|
| 1 | 28 ms | 8 ms | 2.5 ms | 2.3 ms |
| 1,000 | 15 s | 12 s | 1.3 s | 2.4 s |
| 10,000 | | 102 s | 9.2 s | 6.1 s |
| 100,000 | | 943 s (one run) | 210 s | 219 s |

A random origin has about 1,160 segments below it on the walks (1,770 for ltree), so 100,000 origins are 115 M rows (174 M). Within 1 km (about 5 segments an origin) the path walk takes 42 ms at 1,000 origins and 2.6 s at 100,000, the `downstream_id` walk 19 ms and 1.5 s. Every segment of a watershed group, to the outlet: ADMS (10,458) ltree 154 s, path walk 9.4 s, `downstream_id` walk 16 s; BULK (30,046) 199 s, 12 s, 47 s; LFRA (18,180) 101 s, 1.7 s, 2.7 s.

The path walk's time over the `downstream_id` walk's, to the outlet, at defaults (below 1, the path walk is faster):

| batch | path / `downstream_id` |
|---|---|
| 1 random origin | 1.07 |
| random 1,000; 10,000; 100,000 | 0.53; 1.50; 0.96 |
| 1,000 from ADMS; BULK; LFRA | 1.22; 1.25; 2.13 |
| all of ADMS; BULK; LFRA | 0.59; 0.27; 0.66 |

- **Neither walk leads everywhere to the outlet.** At defaults the path walk is faster on random 1,000 and on the three whole groups (up to 3.8 times, BULK), the `downstream_id` walk on random 10,000 and on the three groups' 1,000-origin samples (up to 2.1 times, LFRA).
- **Within 1 km the `downstream_id` walk is 1.7 to 5.5 times faster** on each batch measured, in both passes.
- **Both walks are faster than the ltree join on each batch measured, to the outlet**, at defaults: the path walk 3.3 times at one origin and 4.5 to 58 times on batches, the `downstream_id` walk 3.5 times at one origin and 4.3 to 47 times on batches (at random 1,000: 9.7 and 5.2 times).
- **Workers**, from 11 cells re-run at both settings interleaved, with the `downstream_id` walk (which never uses them, and moved 0.90 to 1.01 between settings) as the control for drift: on those cells, they speed the path walk 1.5 times (random 1,000), 1.7 times (random 10,000) and 7.6 times (BULK, which without workers takes 101 s against the `downstream_id` walk's 52 s); they speed the shipped trace 2 times (random 1,000); they slow the ltree join 1.6 times (random 1,000) and 1.15 times (random 10,000); they leave the 1 km walks unchanged. At one origin the two passes give the same times for every method. The other cells were not interleaved; their no-worker times come from a later pass and mix the setting with drift between runs.
- **Per origin, both walks slow from 10,000 to 100,000 origins** (at defaults, the path walk from 0.9 to 2.1 ms an origin, the `downstream_id` walk from 0.6 to 2.2 ms) while the join holds at 9 to 10 ms; that was not investigated.
- **The path predicate is a poor fit as a join condition:** 15.5 s for one origin, because it is evaluated on every segment of the province, and 1,000 origins time out at 30 minutes.

## Answers to #30

**2. Paths against a `downstream_id` walked recursively.** Neither is ahead on both counts. On speed the two trade places: to the outlet either leads by up to about 3.8 times depending on the batch, within 1 km the `downstream_id` walk is 1.7 to 5.5 times faster, and the path walk gains from parallel workers, which the recursive walk does not use. On accuracy the `downstream_id` walk is ahead: of 4,000 origins the two differ on 24, and in 21 of those the path walk drops a segment or stops early (Risks, above). Given the main-flow tree, the table costs 142 s and 385 MB on top of the paths.

**3. Array against ltree.** The arrays are cheap: a walk unnests about four junctions an origin and reads one index range per line, and runs 5 to 12 times faster than the `FWA_Downstream()` join at 1,000 origins. The two return different sets (the water's path against the code set), so the comparison is of two different answers. Used as a join condition, the path predicate `blk_on_or_upstream()` is evaluated against every segment and takes about 15 s for one origin; a walk, not the predicate, is the way to use the paths.
