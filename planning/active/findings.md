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

Hope trace (`fwa_downstreamtrace(356364114, 160400)`, 536 rows): warm-up 2,667 ms, then 1,084, 1,085 and 1,093 ms; **median 1,085 ms warm**. The 6.8 s planning number was a cold probe.

## Plan review

A Plan-agent critique of the approved plan returned 24 findings (`review-plan.md`); all were folded into the plan before the baseline. The ones that changed the design: L1 reads a smaller table (new class `absent_from_fwa_streams`); A and P share a per-segment `step_m` so their distances compare at all; rules 1–3 apply to every segment, null only when none applies; the paths are re-timed before the pointer build; cells are one psql call each so a timeout is a recorded result; the array predicate `blk_on_or_upstream` gets its own cell (#30's third question); the cycle check is one reverse walk from the roots; the Hope fixture is `sum(st_length)`, not `cum_m`.

## Errors Encountered

| Error | Resolution |
|-------|------------|
