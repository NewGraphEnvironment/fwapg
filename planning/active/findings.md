# Findings — Measure downstream queries: ltree, blue line path arrays, and a downstream_id from the main-flow tree (#34)

## Issue context

**If done:** we know which way of walking downstream serves fresh, wet and link (ltree, the blue line path arrays, or a `downstream_id` from the main-flow tree), with numbers, and #30's questions 2 and 3 are answered with those same numbers. **If never:** consumers build on a shape chosen without measurement.

### Problem

#30 asks:

- whether materialised paths (`fwapg.blk_paths`) beat a `downstream_id` column filled by the same trace and queried recursively;
- how the array downstream query performs against an ltree query, and whether the `fwa_` functions could use it.

Neither has been measured. The main-flow tree (#2) has 0 splits province-wide, so every segment in it has exactly one next segment: a `downstream_id` built from the tree is well defined.

### Proposed

On one full provincial fwapg, three ways of answering "the segments downstream of X, in order, to a distance or to the outlet":

1. ltree: `FWA_Downstream()` / `FWA_DownstreamTrace()` as shipped;
2. arrays: `fwapg.blk_paths` via `fwapg.blk_on_or_upstream()`;
3. `downstream_id`: a column (or lookup table) from the tree, walked with a recursive CTE.

For each, measure:

- build time and size (index included) for the arrays and the `downstream_id`;
- query time for single points and batches (1, 1,000, 100,000 origins), for short walks (1 km), long walks (to the outlet), and for small and large groups (e.g. ADMS, BULK, a Fraser main-stem group);
- correctness: the same downstream set and order for a sample of origins, with every disagreement attributed (local-code anomalies such as #3, side channels, gaps the tree logs).

Record the method and numbers in `research/`, and answer #30 from them.

Points to settle: whether `downstream_id` lives on `fwa_stream_networks_sp`, which upstream would have to accept as a schema change, or in its own lookup table like the tree; and how segments outside the tree (side channels) enter it.

*The plan (method, contract, pointer rules, cells, correctness classes) is in the issue body under `## Plan`.*

## Plan-mode probes (2026-10-21, local Docker PostgreSQL 17.5, 128 GB machine, 16 cores)

Measurement database: `shared_buffers` 32 GB, `work_mem` 2 GB, `effective_cache_size` 96 GB, `max_parallel_workers_per_gather` 8, ltree 1.3. No `fwapg.db_version` table (migrations never run there); the only migration redefines `fwa_watershedatmeasure`, so the downstream functions are current. The shared database (PostgreSQL 16.2, `shared_buffers` 4 GB, 2 workers, migration 202610131654 applied) has no `fwapg.blk_*` tables and no tree, and is upstream-managed: not used.

| object | rows | size |
|---|---|---|
| `whse_basemapping.fwa_stream_networks_sp` | 4,907,441 | 10,013 MB total, 6,763 MB heap |
| its code indexes: `wsc_gist` 545 MB, `wsc_btree` 450 MB, `lc_gist` 503 MB, `lc_btree` 425 MB; `blkey_measure` 191 MB | | |
| `fwapg.blk_paths` | 1,570,499 | 228 MB (PK 34 MB) |
| `fwapg.blk_parents` | 1,570,499 | 136 MB (PK 34 MB); junction methods: code 1,467,190, touch 71,331, touch_round 29,691, side_fallback 2,250, code_deferred 37 |
| `whse_basemapping.fwa_stream_networks_mainflow_tree` | 4,510,368 | 482 MB; sources: mainflow 4,451,744, reattached 58,447, followed 177 |
| `fwapg.mainflow_tree_qa` | 504 | dead_end 473, no_parent 23, cut_off 8, split 0 |
| segments not in the tree | 397,073 | |
| segments absent from `whse_basemapping.fwa_streams` (what `fwa_downstreamtrace` reads) | 369,217 | |

Network facts the pointer rules rely on:

- 0 blue lines with two segments at one `downstream_route_measure`;
- edge type 6010: 250 segments; 1425: 343; `wscode_ltree <@ '999'`: 208,189; null `wscode_ltree`: 0;
- 212,790 blue lines (366,162 segments) have no `fwapg.blk_paths` row: outlets at the sea or a border, water leaving BC before its parent, codes under 999;
- 1,099 blue lines whose lowest `downstream_route_measure` is above 1 mm;
- the Fraser is `blue_line_key` 356364114 (4,271 segments, 1,404 km, 13 watershed groups); 246 watershed groups, from 2,147 to 66,083 segments; ADMS 11,520, BULK 32,472, LFRA 19,991, FRAN 31,911, UNRS 25,514, LNRS 10,341.

Timings:

| form | rows | time |
|---|---|---|
| `fwa_downstreamtrace(356364114, 160400)` (Hope) as shipped | 536 | 6.8 s, cache state not recorded |
| `fwa_downstream()` as a join predicate from Hope, ids only | 544 | 381 ms; BitmapOr over `fwa_streamnetworks_blkey_measure_idx` and `fwa_streamnetworks_wsc_gist_idx` (`wscode_ltree @> '100'`, 6,980 index rows, 6,436 removed by the filter) |
| the same predicate, five seeded random origins in one statement | 5,542 | 663 ms cold, 115 ms warm (one PARA origin at code depth 5: 1,676 rows) |
| array walk from Hope, main chain, `drm < junction − 1 mm` | 239, 161.40 km (the `docs/03_functions.md` fixture exactly) | 48 ms |
| array walk, 200 seeded random origins | mean 1,143 segments and 388 km an origin; max 3,932 and 1,279 km | 2.48 s, 12 ms an origin |

## Phase 1: environment and origins (2026-10-21, `logs/env_*`, `logs/origins_*`, `logs/hope_*`)

Settings at the measurement (server defaults): PostgreSQL 17.5, ltree 1.3, PostGIS 3.5.2, `jit` on, `max_parallel_workers_per_gather` 8 (`max_parallel_workers` 14), `work_mem` 2 GB, `hash_mem_multiplier` 2, `shared_buffers` 32 GB, `effective_cache_size` 96 GB, `random_page_cost` 1.1. The database sits on a Docker Desktop volume (grpcfuse) on the 16-core, 128 GB machine.

Sizes as in the planning table, plus `fwa_streams` 4,538,224 rows, 8,148 MB total, and its code indexes (`wsc_gist` 451 MB, `wsc_btree` 385 MB, `lc_gist` 477 MB, `lc_btree` 407 MB, `blkey_measure` 172 MB).

Assertions held: no blue line has two segments at one `downstream_route_measure`; every tree segment is a network segment. Re-measured: 369,217 segments absent from `fwa_streams`, 397,073 not in the tree, 1,099 lines whose lowest segment starts above 1 mm, 212,790 lines (366,162 segments) with no path.

**New: 328,961 segments have a null `localcode_ltree`** (null `wscode_ltree`: 0). 170,773 of them are under 999; the other 158,188 are on the network, mostly edge types 1450 (71,534), 1100 (50,279) and 1350 (33,064). The ltree predicate's code criteria are null for them, so L2 returns them only on the origin's own blue line (criterion 1). The `code_999` class covers them: a segment under 999 or with a null local code.

Origins (`fwapg.bench_origins`, seeded rank `md5('fwapg#34:' || linear_feature_id)`; eligible: both codes non-null, not under 999; 366,377 segments excluded province-wide):

| grp | origins | in tree | with a path | in `fwa_streams` | excluded |
|---|---|---|---|---|---|
| random | 100,000 | 99,339 | 96,597 | 99,938 | |
| random 1..1,000 | 1,000 | 993 | 958 | 999 | |
| ADMS | 10,458 | 10,458 | 10,448 | 10,449 | 1,062 |
| BULK | 30,046 | 30,046 | 30,046 | 30,037 | 2,426 |
| LFRA | 18,180 | 18,175 | 17,790 | 18,154 | 1,811 |

Hope trace (`fwa_downstreamtrace(356364114, 160400)`, 536 rows), idle server (`logs/hope_20261021T161512Z.log`): warm-up 1,889 ms, then 953, 954 and 926 ms; **median 953 ms warm**. The 6.8 s planning number was a cold probe.

**A concurrent query was running through the first measurements.** An orphaned psql query (a QA check on the `pcic` tables, started 2026-10-20 13:37 UTC, no client process left on the machine, 6 parallel workers, the container at about 700 % CPU) had run for 26 h. It read only and its result had no receiver, so it was cancelled (`pg_cancel_backend`) at 16:15 UTC; the container then idled at 0 % CPU. The env and origins steps ran under it (they measure nothing time-sensitive). The first Hope run (`logs/hope_20261021T161337Z.log`: median 1,085 ms) did too, and is superseded by the idle one. Every later step checks `pg_stat_activity` for other client backends first.

## Phase 2: paths re-timed, `downstream_ids` built (2026-10-21, `logs/paths_*`, `logs/ids_*`)

**Blue line paths, re-timed unchanged** (`extras/blue_line_paths/blue_line_paths.sh`, idle server): 992 s wall (16.5 min), QA all `t`. Sorted-row md5s are identical before and after, so the build is deterministic on this data despite the `DISTINCT ON`s with no id tie-break:

| table | rows | md5 before = after |
|---|---|---|
| `fwapg.blk_parents` | 1,570,499 | `5153b43b719febf8b82c8111862e441f` |
| `fwapg.blk_paths` | 1,570,499 | `06a9b844c59f728413467e3751f28731` |

Size, from `00_env.sql`: `blk_paths` 228 MB with its key, `blk_parents` 136 MB; the walk reads only `blk_paths` (and `fwa_stream_networks_sp` through `blkey_measure_idx`).

**`fwapg.downstream_ids`**: 142 s wall (temp node table 22 s, tree up-node key 25 s, line window 17 s + 9 s key, junctions 15 s, the table 23 s, key 18 s), 4,907,441 rows, heap 280 MB, primary key 105 MB, **385 MB total**. The walk needs only the key. Every QA assertion is `t` (`logs/ids_qa_*`): one row per segment, no self pointer, every target a segment, `method` and `step_m` set exactly when `downstream_id` is, `step_m` positive, the walk up from the 213,227 roots reaches every segment once (acyclic and complete), and a tree segment points off the tree only where the tree QA logs it.

| method | in tree | not in tree |
|---|---|---|
| node | 4,483,174 | 64,454 |
| line | 8 | 136,778 |
| junction | 90 | 9,710 |
| null | 27,096 | 186,131 |

- **One refinement to rule 3, made at build time:** where a line's junction is at or below its parent's lowest segment (the parent starts there), the step goes to the next line on the path with a segment below its junction, as the array walk does. 249 lowest segments took a step past their parent.
- **Null in tree, 27,096:** 26,690 outlets, the 23 `no_parent` mouths, and 383 of the 473 dead ends. Those 383 join a parent exactly at the parent's lowest segment start (the parent begins there: its bottom is the junction measure), and every later line on their path does the same, so there is no segment below any junction: the network ends. The array walk ends at the same place (no segment more than 1 mm below the junction). The other 90 dead ends take a junction step onto the tree.
- **The 8 cut-offs** all take a `line` step to the next segment of their own side channel, off the tree (BARR, KITR, KUSR, MESI, OWIK, TATR, LFRA, GOLD; 21 m to 1,515 m), and so continue down the channel the tree dropped.
- **The Beaver River override** (868144443, an excluded 6010 connector): not in the tree, a `node` pointer onto the tree; no segment points to it.
- **Node pointers that leave the blue line while the line continues: 1** (a side channel, not in the tree). The A–P difference by design is therefore almost entirely at line ends, not mid-line.

## Phase 3 harness notes (2026-10-21)

- **The sink dominated the first EXPLAINs** (`logs/explain_20261021T163845Z.log`): A to the outlet at 1,000 origins finished its SELECT in 1.6 s and spent 4.0 s inserting 1.16 M rows. The database files sit on a Docker Desktop host mount, where every relation extension is slow: 1.2 M rows take 4.4 s into new pages (TRUNCATE first) and 0.2 s into pages kept by DELETE and VACUUM. A temp table is as slow (4.5 s). The cost is the mount's, not the method's, so `bench_out` is pre-extended to 200 M rows once (`vacuum_truncate = false`) and emptied with DELETE and VACUUM between repeats. That first EXPLAIN log is kept as the record of the problem; the EXPLAINs are re-run on the pre-extended sink.
- psql `\ir` resolves against the including file's directory, so the cell script (a temp file) uses `\i` against the working directory.
- **Plan corrected: cells time a SELECT, not an INSERT.** PostgreSQL never runs a data-modifying statement in parallel, so `INSERT INTO bench_out SELECT ...` ran every method single-process, and the plan's second pass at `max_parallel_workers_per_gather = 0` would have repeated the first. Each cell now runs the walk under one row of aggregates over every output column (`count(*)`, `bit_xor` of the ids, `sum(ord)`, `sum(cum_m)`), so every row and every window value is computed, nothing is written, and the planner may use workers. The pre-extended sink was dropped. Re-run EXPLAINs (`logs/explain_20261021T171503Z.log`): workers launch for L2 (2) and A (2) at 1,000 origins; to the outlet at 1,000 random origins A takes 1.28 s, P 2.23 s, L2 12.6 s; one origin takes A 0.43 ms, P 3.9 ms, L2 27 ms, L1 91 ms, A-pred 20.3 s (a sequential scan of every segment, no workers).
- The refactored walks return the stored rows exactly (random 1..5, every method and walk); L2's `ord` differs on 96 tied rows between runs, because its sort has no unique key (the `code_tie_across_lines` class).

## Phase 3: timings (2026-10-21 17:16–21:29 UTC, `logs/cell_*`, `logs/summary_20261021T212933Z.log`)

The matrix ran unattended on the idle server, defaults then `max_parallel_workers_per_gather = 0`, every cell a warm-up and three repeats (median reported) except L2's budget cells (one run, no warm-up: each finished inside its 30 min timeout, so none is projected). Each statement is the walk under one row of aggregates over every column. Times are medians in ms unless marked s; "np" is the no-parallel pass. After review round 1 the single-origin cells, L1 at 1,000 (now warm-up and three repeats) and a no-origin cell were re-run with the walk files' dispatch query moved out of the timed interval; those re-runs replaced the cells' rows.

**Fixed cost of a statement** (no origins: planning and the timing round trips): L1 0.9, L2 1.1, A 1.3 (1 km 1.6), P 0.9 ms; A-pred 55 ms.

**Random origins, to the outlet** (default / np):

| origins | L1 | L2 | A-pred | A | P |
|---|---|---|---|---|---|
| 1 (median of 20; p95) | 28.5; 38.7 | 8.2; 16.9 | 15.5 s; 17.4 s | 2.5; 4.4 | 2.3; 4.5 |
| 100 | 2.9 s / 2.8 s | | | | |
| 1,000 | 14.7 s / 29.2 s | 12.3 s / 7.6 s | timeout (30 min) | 1.26 s / 1.31 s | 2.38 s / 1.71 s |
| 10,000 | | 102 s / 62 s | | 9.2 s / 11.6 s | 6.1 s / 5.2 s |
| 100,000 | | 943 s / 607 s (1 run) | | 210 s / 348 s | 219 s / 196 s |

Rows at 1,000 random origins: L1 1.76 M, L2 1.77 M, A 1.156 M, P 1.156 M; at 100,000: L2 174 M, A and P 115 M.

**Random origins, 1 km**: 1 origin A 1.45, P 0.78 ms (both at the fixed cost); 1,000: A 42 / 31 ms, P 19 / 15 ms; 10,000: A 382 / 306 ms, P 198 / 160 ms; 100,000: A 2.6 / 2.4 s, P 1.5 / 1.3 s (about 5 segments an origin).

**Whole groups, to the outlet** (default / np): ADMS (10,458 origins) L2 154 / 124 s, A 9.4 / 16.5 s, P 16.1 / 15.8 s; BULK (30,046) L2 199 / 216 s, A 12.5 / 100 s, P 46.8 / 48.6 s; LFRA (18,180) L2 101 / 137 s, A 1.7 / 2.5 s, P 2.7 / 3.0 s. Each group's seeded 1,000 sits in the same order (`logs/summary_*`).

What the numbers say:

- **The array walk and the pointer walk are within a factor of two of each other, except on BULK with workers (A 3.7 times faster)**, and which is ahead depends on the walk and on workers: A leads to the outlet at 1,000 origins and on whole groups with workers (BULK 12.5 s against 46.8 s); P leads at 10,000, at 100,000 without workers, on every 1 km walk (about twice as fast), and on BULK without workers (48.6 s against 100 s). P never uses workers (a recursive CTE is parallel-restricted), so its two passes agree; A's window sort uses them.
- **Both are 4 to 17 times faster than the ltree join** (same settings): 4–10 times at 1,000 origins (A 1.26 / 1.31 s, P 2.38 / 1.71 s, L2 12.3 / 7.6 s), 5–17 times at 10,000, and 1.7–4.5 times at 100,000. Per origin both slow from 10,000 to 100,000 (A 0.9 to 2.1 ms, P 0.6 to 2.2 ms with workers) while L2 holds at 6–12 ms; that rise was not investigated (115 M rows; a window sort and a recursive tuplestore that large may spill past `work_mem`).
- **Workers slow L2**: without them it is faster at 1,000 (7.6 s against 12.3 s), 10,000 and 100,000; L1 is the reverse (29 s against 15 s at 1,000).
- **The array predicate is unusable as a join**: 15.5 s for one origin (a sequential scan of every segment, the predicate's `EXISTS` evaluated on each), and 1,000 origins time out at 30 min (projected 4.3 h).
- **The shipped trace** costs 28 ms an origin, warm, and grows linearly (2.9 s at 100, 14.7 s at 1,000 with workers).

## Phase 4: correctness (2026-10-21, `logs/results_*`, `logs/compare_*`)

Run before the timings, because the comparison queries would load the server under the timed cells. `07_results.sql` writes each method's rows for the samples into `fwapg.bench_res` (untimed): L2, A, P (to the outlet) and A, P (1 km) on random 1..1,000 and each group's 1..1,000 (4,000 origins); L1 on random 1..100; A-pred on random 1..20. `07_compare.sql` writes every set, order and distance difference into `fwapg.bench_diffs` and attributes each by ordered predicates. **No difference is unattributed**, and A and P agree on every `cum_m` wherever their sets agree (the largest difference there is 0 m, logged: they sum the same `step_m` in the same order).

| pair | kind | class | segments | origins | what it is |
|---|---|---|---|---|---|
| A–P | set | `path_ends` | 3,077 | 4 | the chain's last line (the origin's or the last on its path) has no path of its own; A stops at its mouth, P goes on through the node; A is a prefix of P |
| A–P | set | `code_junction_below_node` | 17 | 17 | the code junction is the start of the parent segment whose top is the tributary's mouth: A drops that one segment, P keeps it (P is right) |
| A–P | set | `route_differs` | 21 | 3 | the tree and the paths send the water down different lines, and the walks rejoin (same last segment) |
| A–P 1 km | set | the same three | 23 | 7 | the same segment's full-walk class, or that of a full-walk difference within the first 1 km |
| L2–A | set | `side_channel` | 1,640,569 | 3,837 | non-main lines the water does not pass through, which the codes count (0 on a main line, checked) |
| L2–A | set | `path_ends` | 31,430 | 29 | the paths stop; the codes go on down the last line's code ancestors (or, for a pathless side channel, its own main stem) |
| L2–A | set | `alongside_side_channel` | 2,325 | 475 | the main stem beside a side channel the water is in: the codes count it from where the side channel leaves |
| L2–A | set | `path_through_side_channel` | 1,919 | 702 | the path takes the water through a braid it touches; the codes do not count the braid |
| L2–A | set | `localcode_anomaly` | 550 | 264 | local codes out of order with the measures, or nested deeper than one level, at the segment or (on a chain line) at the origin (#3's shape) |
| L2–A | set | `code_parent_bypassed` | 94 | 20 | a main line whose code is an ancestor of the origin's, which the path passes by: the water reaches a line further down by a touch |
| L2–A | set | `side_channel_rejoin` | 91 | 25 | main-stem segments below where a side channel rejoins carry its local code, and the codes need a strictly lower one |
| L2–A | set | `code_999` | 47 | 23 | null local code: the codes cannot place it |
| L2–A | order | `localcode_anomaly` | 43,320 | 3,688 | 1,242 distinct segment pairs: a segment downstream of the one before it on the same line, with a greater local code |
| L2–A | order | `code_tie_across_lines` | 53 | 45 | two lines at the same codes; the code order breaks the tie by measure, which across lines says nothing |
| L2–A | order | `path_through_side_channel` | 9 | 9 | |
| L2–P | | the L2–A class where A and P agree on the segment, the A–P class where they do not | | 3,856 | |
| L1–L2 | set | `absent_from_fwa_streams` | 1,495 | 86 | the shipped trace reads `fwa_streams`, which lacks them; no origin was dropped |
| L1–L2 | order | `code_tie_across_lines` | 1,772 | 80 | the trace's `ORDER BY` has no unique key: lines that share codes and start at measure 0 tie |
| A-pred–A | set | `junction_at_segment_start` | 73 | 20 | the shipped predicate compares measures inclusively and counts the segment that starts at the junction; the walk does not |

The classes were tightened after review round 1 (`logs/compare_20261021T21*`): side channels must be on non-main lines, which exposed 15,188 main-line segments a broader class had absorbed, now `path_ends` and `code_parent_bypassed`; `route_differs` requires the walks to rejoin; `path_ends` requires the array walk to be a prefix of the pointer walk. The results were regenerated with the final walk files first. The largest A–P distance difference where the sets agree is logged: 0 m, to the outlet and at 1 km.

The local-code predicate discriminates: it flags 7.3 % of the array walk's segments (1 in 50 sample, 218 of 2,973) and every set difference it explains. Of the L2–A order differences, 43,320 of 43,382 are a downstream segment on the same line with a greater local code than the one above it.

**Hope fixture** (`fwa_downstreamtrace` origin, `sum(ST_Length)` over whole segments):

| method | segments | km whole | km main flow | outlet `cum_m` |
|---|---|---|---|---|
| A | 239 | 161.40 | 161.40 | 160.400 km |
| P | 239 | 161.40 | 161.40 | 160.400 km |
| L2 | 544 | 309.70 | 161.40 | |
| L1 | 536 | 307.81 | 161.08 | |

161.40 km holds for A, P and L2's main flow. **The docs' 308.54 km is stale:** the documented query, run verbatim, returns 309.70 km (544 segments) on this load. L1's main flow is 0.32 km shorter because its trace cuts the origin's segment at the measure; its total is lower for that and for the 8 segments absent from `fwa_streams`.

## Plan review

A Plan-agent critique of the approved plan returned 24 findings (`review-plan.md`); all were folded into the plan before the baseline. The ones that changed the design: L1 reads a smaller table (new class `absent_from_fwa_streams`); A and P share a per-segment `step_m` so their distances compare at all; rules 1–3 apply to every segment, null only when none applies; the paths are re-timed before the pointer build; cells are one psql call each so a timeout is a recorded result; the array predicate `blk_on_or_upstream` gets its own cell (#30's third question); the cycle check is one reverse walk from the roots; the Hope fixture is `sum(st_length)`, not `cum_m`.

## Errors Encountered

| Error | Resolution |
|-------|------------|
