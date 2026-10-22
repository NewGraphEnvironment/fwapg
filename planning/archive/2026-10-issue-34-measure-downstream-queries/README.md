# Measure downstream queries: ltree, blue line path arrays, and a downstream_id (#34)

## Outcome

Built a benchmark harness (`scripts/bench.sh` and its SQL) and measured five ways of walking downstream on the full provincial FWA: the shipped `fwa_downstreamtrace` (L1), the `fwa_downstream` predicate as a join (L2), `fwapg.blk_on_or_upstream` as a join (A-pred), a walk over the blue line path arrays (A), and a new `fwapg.downstream_ids` pointer table walked by recursive CTE (P), built from the main-flow tree's node matches, the next segment on a line, and the path junctions. Every set, order and distance difference between the methods on 4,000 origins is attributed to a cause by a SQL predicate, none left over. The two walks return the water's path and agree on 3,976 of 4,000 origins, to 0 m in distance; ltree returns the code-described set, about 1.4 times larger (side channels), ordered by codes that run out of order along lines. Neither walk wins everywhere, so the paths stay what the extras use and no follow-up issue was filed; the array predicate is unusable as a join. The durable verdict is [`research/fwa_downstream_queries.md`](../../../research/fwa_downstream_queries.md), which answers #30's questions 2 and 3.

Wrong turns kept: the first Hope timing ran under an orphaned 26 h query holding 7 cores (cancelled, re-run); the first sink, an INSERT, was dominated by page extension on the Docker Desktop host mount and also barred parallel plans (replaced by an aggregate over every column); the dispatch query sat inside the timed interval (moved out, small cells re-run); the default and no-parallel passes were confounded with time (an interleaved A B B A re-run of 11 cells, with the pointer walk as the drift control, replaced the settings claims); several correctness classes were broader than their names (tightened over three review rounds, which exposed main-line segments a side-channel class had absorbed); and comparative claims written by eye from the tables were wrong until each was read off a logged ratio table and checked as written (round 4 enumerated 141).

## Measurement

One machine, 16 cores, 128 GB, PostgreSQL 17.5 in Docker Desktop, warm cache, server defaults unless stated; medians of three after a warm-up.

- Builds: blue line paths 992 s, 228 MB (deterministic: identical sorted-row md5s before and after); `downstream_ids` 142 s, 385 MB, on top of the paths and the main-flow tree; QA all true (acyclic and complete by one walk up from 213,227 roots).
- To the outlet, random origins (L1 / L2 / A / P): 1 origin 28 / 8 / 2.5 / 2.3 ms; 1,000 origins 15 / 12 / 1.3 / 2.4 s; 10,000 — / 102 / 9.2 / 6.1 s; 100,000 — / 943 (one run) / 210 / 219 s. A-pred: 15.5 s for one origin, 1,000 timed out at 30 min.
- Within 1 km the pointer walk is 1.7 to 5.5 times faster than the array walk; to the outlet either leads by up to 3.8 times depending on the batch.
- Workers (interleaved, 11 cells): speed the array walk 1.5 to 7.6 times, slow the ltree join 1.15 to 1.6 times; the pointer walk's plans use none.
- Correctness: A and P differ on 24 of 4,000 origins (17 code junctions one segment below the mouth node, 4 where the paths stop, 3 rejoining routes); the docs' Hope total of 308.54 km is stale (309.70 km), 161.40 km of main flow holds.

These turned the plan's open question (paths or `downstream_id`) into a measured tie with known edges, and turned "array functions are expensive" into a measurement: the walk is cheap, the predicate as a join is not.

## Evidence

`logs/` in this directory: `env_*`, `origins_*`, `hope_*` (the 16:13 run is the one under load), `paths_*`, `ids_*`, `explain_*` (the 16:38 one is the INSERT-sink record), `cell_*` (the timing matrix and its re-runs), `timings_run_*`, `ab_run_*` and `cell_*_ab*` (the interleaved run), `results_*`, `compare_*` (each iteration of the classes; the newest is final), `summary_*` (the newest holds the ratio and interleaved lines). Review findings: `review-*.md`.

Closed by: PR into `newgraph` (see the branch `34-measure-downstream-queries-ltree-blue-li`)
