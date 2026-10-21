# Task: Measure downstream queries: ltree, blue line path arrays, and a downstream_id from the main-flow tree (#34)

#30 asks:

- whether materialised paths (`fwapg.blk_paths`) beat a `downstream_id` column filled by the same trace and queried recursively;
- how the array downstream query performs against an ltree query, and whether the `fwa_` functions could use it.

Neither has been measured. The main-flow tree (#2) has 0 splits province-wide, so every segment in it has exactly one next segment: a `downstream_id` built from the tree is well defined.

The method, the contract the three methods share, the pointer rules, the cells and the correctness classes are in the issue body under `## Plan` (approved 2026-10-21, with a Plan-agent critique of 24 findings folded in; `review-plan.md`).

## Phase 1: harness and origins
- [ ] `planning/active/scripts/bench.sh`: one psql call per step and cell against `DATABASE_URL`, `\timing`, timeouts recorded and the run continued, no `set -x`, logs to `planning/active/logs/<step>_<date>.log` with the URL redacted
- [ ] `sql/00_env.sql`: named settings, table and index sizes, and assertions: `(blue_line_key, downstream_route_measure)` unique, segments absent from `fwa_streams`, lines whose bottom is above 1 mm — into `findings.md`
- [ ] `sql/00_origins.sql`: `fwapg.bench_origins` as above
- [ ] The Hope trace re-run under the harness, warm, beside the 6.8 s probe

## Phase 2: paths and `downstream_id`
- [ ] Re-time `blue_line_paths.sh` with sorted-row md5s of both tables before and after; on a mismatch, diff and attribute
- [ ] `sql/01_downstream_ids.sql`: the table with `step_m`, rules 1–4, timed and sized
- [ ] `sql/01_qa.sql`: the assertions; the 8 cut-offs, the override, and node pointers that leave a continuing line, listed

## Phase 3: queries and timings
- [ ] `sql/02_walk_ltree.sql`, `03_walk_arrays.sql`, `04_walk_pointer.sql`: L1, L2, A-pred, A, P as inline statements with psql variables, both walks
- [ ] `sql/05_explain.sql`: `EXPLAIN (ANALYZE, BUFFERS)` per method and walk at 1 and 1,000 origins, in the logs
- [ ] `sql/06_timings.sql`: the cells at defaults and at `max_parallel_workers_per_gather = 0`, into `fwapg.bench_timings(method, walk, cell, settings, repeat, ms, rows, note)`, projected rows beside each
- [ ] Table of medians, timeouts and projections in `findings.md`

## Phase 4: correctness
- [ ] `sql/07_compare.sql`: set, order and distance differences into `fwapg.bench_diffs`, each class a predicate
- [ ] Unattributed class empty, or the run is not done
- [ ] Hope fixture as `sum(st_length)`, each method

## Phase 5: write-up
- [ ] `research/fwa_downstream_queries.md` (Verified / Issues / Produced by line; what works, the numbers with units, which table each method reads, what each cannot do) and its row in `research/README.md`
- [ ] Archive README with `## Measurement` and `## Evidence` (logs by glob)
- [ ] Comment on #30 with the headline numbers and the research link (our repo; the earlier reply promised it)
- [ ] If `downstream_id` wins: file the follow-up issue to land it as an extra with a load file and published output, as the lookup table decided at the plan gate

## Validation
- [ ] QA and comparison assertions pass
- [ ] `/code-check branch`
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive`
