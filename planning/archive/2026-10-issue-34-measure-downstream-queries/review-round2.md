# Review round 2 (#34)

Scope: `planning/active/scripts/bench.sh`, `scripts/sql/*.sql`, `research/fwa_downstream_queries.md`, `planning/active/findings.md`, against `logs/compare_20261021T215544Z.log`, `logs/summary_20261021T212933Z.log`, the cell logs and read-only queries on the local database (2026-10-21 ~22:00 UTC).

**dispatch_given (focus 2): clean.** Only the `bench.sh` cell script sets `dispatch_given`, and it sets all three flags from that cell's own method and walk. Each cell is its own psql process, so no flag carries over to another cell. `05_explain.sql`, `07_results.sql` and the Hope section of `07_compare.sql` never set it, so each of their `\ir` includes runs the dispatch query again for the current `:method`/`:walk`. `04_walk_pointer.sql` uses no flags. After `\i`, the walk is still the last statement, so `:ERROR` reads the walk.

## Findings

- **[bug] `scripts/sql/07_compare.sql:304-319` — the L2–A `path_ends` class counts side channels that the paths stopping does not explain. Because it runs before `side_channel`, it takes those cases away from that class.**
  - The first branch (`c.wscode != x.wscode_ltree`) has no `x.is_main` and no check on position.
  - 11,687 of the 31,430 L2–A `path_ends` rows are on non-main lines.
  - For 14 of its 29 origins, every row is on a non-main line: origins 149411, 149421, 149543, 149611, 149781, 151968, 152199, 152248, 152363, 152439, 153219, 153295, 153355 and 153498.
  - Each of those origins has 21 rows, on 8 side channels of the Columbia in KHOR and COLR (for example 706675623, 707028202 and 706638658). Those side channels carry `wscode = localcode = '300'`.
  - The chain of these origins ends on a Kettle line (`300.571168`), which reaches the Columbia outside BC. The 21 segments lie in the upper Columbia, above that junction. The codes count them because a local code of bare `300` sorts below everything on the Columbia, not because the paths stop.
  - The same three segments are classed `side_channel` 204 times and `path_ends` 42 times, depending only on the origin.
  - Fix: require `x.is_main` in the first branch as well, or run `side_channel` before `path_ends`. Then update the research table row ("31,430 | 29") and findings line 167.

- **[bug: wrong conclusion] `findings.md:150` and `research/fwa_downstream_queries.md:64` say "P never uses workers … so its two passes agree". The summary shows otherwise, and the gap shows that settings are confounded with time.**
  - P's default and no-parallel passes differ systematically, with tight repeats:
    - 1,000 origins: 2.38 s vs 1.71 s (39%; reps 2.32–2.43 vs 1.71–1.73).
    - 10,000: 6.13 vs 5.23 s.
    - 100,000: 219 vs 196 s.
    - 1 km at 1,000: 18.7 vs 15.1 ms.
    - BULK_1000 1 km: 6.95 vs 9.00 ms, which goes the other way.
  - The EXPLAIN in `logs/explain_20261021T171503Z.log` has no Gather for P at 1,000, so the plan does not depend on workers.
  - Every default cell ran first (17:16–19:18) and every no-parallel cell after it (19:18–21:25). A 12–39% shift that has nothing to do with the setting is therefore part of every "with / without workers" comparison.
  - Affected claims: "Workers slow the ltree join" (1.55–1.65 times), A's 1.26 vs 1.31 s and LFRA_1000 A 394 vs 149 ms. The worker effects can no longer be read off as they stand.
  - Either remove the sentence and state the drift, or interleave the settings per cell.

- **[bug: wrong claim] `research:64` and `findings:150` say "within a factor of two of each other, except on BULK with workers". At least six other pairs of cells exceed a factor of two. In every case P is the faster:**
  - random 10,000 without workers: 11.6 vs 5.2 s, 2.22 times;
  - BULK whole without workers: 100 vs 48.6 s, 2.06 times. Findings line 150 cites this pair itself;
  - LFRA_1000 with workers: 394 vs 185 ms, 2.13 times;
  - 1 km at random 1,000: 41.8 vs 18.7 ms (2.24 times) and 30.6 vs 15.1 ms (2.04 times);
  - 1 km on the group 1,000s: ADMS 5.3 and 5.5 times, BULK 4.7 and 2.9 times, LFRA 3.7 and 3.3 times.

  The same cells contradict "on every 1 km walk (about twice as fast)", and the 10,000 cell contradicts "up to twice as fast" in `research:71`.

- **[bug: wrong claim] `research:64` and `research:71` say "the array walk leads … at 1,000 origins", and `findings:146` says "Each group's seeded 1,000 sits in the same order".**
  - With workers, P leads on all three groups' 1,000-origin subsamples: ADMS 1.53 vs 1.87 s, BULK 1.06 vs 1.32 s, LFRA 0.185 vs 0.394 s.
  - On the whole groups with workers, A leads on all three.
  - Without workers the order reverses again: on ADMS whole P is ahead (15.75 vs 16.46 s), and on ADMS_1000 A is ahead (1.36 vs 1.40 s).
  - So the subsamples do not sit in the same order, and "leads at 1,000 origins" holds only for the random 1,000.

- **[bug: wrong claim] `findings:154` says "grows linearly (2.9 s at 100, 14.7 s at 1,000 with workers)", and `findings:152` and `research:66` say the shipped trace is "the reverse".**
  - 14.7 s at 1,000 is half of linear (28.6 ms × 1,000 = 28.6 s).
  - The cause is a change of plan. EXPLAIN now gives the 1,000-origin L1 statement a `Gather` (1 worker) over a `Parallel Bitmap Heap Scan on bench_origins`, so the origins split across two processes. The 100-origin statement has no Gather.
  - At 100, workers do not speed L1 up: 2.86 s with them, 2.80 s without.
  - The first run of the same default cell (`cell_L1_full_1000_default_20261021T173702Z.log`, 17:37) took 28.9 s. The 21:26 re-run took 14.7 s, with the same statement and settings. That is an unexplained factor of two, and the claim rests on the second run alone.
  - Cells do not record `Workers Launched`, so no cell in the "with workers" pass can be shown to have had workers.

- **[bug: wrong number] `findings.md:182` says "exposed 15,188 main-line segments".**
  - 15,188 is the drop in `side_channel` between the pre-review run (1,661,801, `compare_20261021T170814Z`) and an intermediate run (1,646,613, `compare_20261021T213904Z`).
  - Against the final run (1,640,569, `compare_20261021T215544Z`) the number is 21,232. It matches the move into `path_ends` (10,292 → 31,430, which is +21,138) plus `code_parent_bypassed` (94).
  - Also, the moved segments are not all main-line: of the 31,430, 11,687 are non-main (first finding).

- **[bug: wrong number, minor] `research:73` says "The array walk is 4 to 10 times faster than the ltree join at 1,000 origins".** The array walk alone is 5.8 to 9.7 times faster (12.27/1.26 and 7.58/1.31). The 4 comes from the pointer walk (7.58/1.71 = 4.4).

- **[bug: wrong number, minor] `research:65` says "both slow per origin (from about 1 ms to about 2 ms)".** Without workers, A goes from 1.16 to 3.48 ms an origin. `findings:151` scopes the same figure "with workers"; the research sentence does not.

- **[fragile] `scripts/sql/07_compare.sql:207` — `AND EXISTS (SELECT 1 FROM cmp_lines c WHERE c.origin_id = d.origin_id AND c.is_last)` is always true.**
  - `is_last` is `step = max(step)` per origin, so every origin has such a row.
  - The clause reads as the check behind the class's story ("has no path of its own, because its water leaves BC … or it has no parent"), but it checks nothing.
  - The attribution currently rests entirely on the prefix test above it. Remove the clause, or replace it with a real condition, such as one on `blk_parents.junction_method` for the last line.

- **[fragile] `logs/compare_20261021T215544Z.log:1` contains `WARNING:  could not truncate file "base/16384/221537280": Input/output error`.**
  - This is the run whose numbers the research and findings cite. The warning came from the `DROP TABLE fwapg.bench_diffs` at line 64.
  - The filesystem under the data directory returned EIO, which fits the Docker Desktop host-mount problems noted in the Phase 3 harness notes.
  - Findings and progress do not mention it. A storage I/O error during the evidence run should be investigated, and stated if it is benign, before the logs are cited as clean.
