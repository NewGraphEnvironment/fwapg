# Review round 4b: terminal enumeration of research/fwa_downstream_queries.md and comment30.md

Sources checked: `logs/summary_20261021T231626Z.log` (rows, `ratio`, `ab`), `logs/compare_20261021T231634Z.log`,
`logs/ids_qa_20261021T163511Z.log`, `logs/ids_20261021T163246Z.log`, `logs/paths_20261021T161539Z.log`,
`logs/env_20261021T161045Z.log`, `logs/hope_20261021T161512Z.log`, `logs/explain_20261021T171503Z.log`,
`fwapg.bench_diffs` / `bench_origins` / `bench_cells` / `blk_paths` and `fwa_stream_networks_sp` (read-only SELECTs),
`docs/03_functions.md`, `load/fwa_streams.sql`, `extras/mainflow_tree/sql/*.sql`, the walk SQL.

## Findings

- **[bug, security]** `planning/active/logs/ab_run_20261021T220843Z.out` (44 lines, `log: /Users/<user>/Projects/repo/fwapg/...`) — the local username and home layout. Committed in 440a363 and already on `origin/34-measure-downstream-queries-ltree-blue-li` (public fork). The round-1 redaction covered psql NOTICE lines and `timings_run_*.out`, not the A/B runner's `log:` lines. Redact the file, and since the commit is pushed, the branch history carries it until rewritten (or the PR is squash-merged and the branch deleted). The research file and comment30.md themselves are clean (no hosts, paths or credentials).
- **[bug]** `research/fwa_downstream_queries.md:15` — "orders by codes, which is not flow order where local codes run out of order along a line (#3's shape: 1,242 distinct segment pairs on the 4,000 origins' chains)". `compare` logs 1,242 for *all* L2–A order differences as distinct (segment, previous segment) pairs. By class (`SELECT class, count(*) FROM (SELECT DISTINCT linear_feature_id, prev_linear_feature_id, class FROM fwapg.bench_diffs WHERE pair='L2-A' AND kind='order') x GROUP BY 1`): `localcode_anomaly` 1,208, `code_tie_across_lines` 31, `path_through_side_channel` 3. #3's shape is 1,208; the 31 tie pairs are the sentence's *other* cause ("two lines share both codes").
- **[bug]** `research/fwa_downstream_queries.md:15` — "It misses segments with a null local code (158,188 on the network, …)". The network has **328,961** segments with a null `localcode_ltree` (`env` log "null code 328961"; re-counted). 158,188 is the subset *outside* the 999 codes (`findings.md:77` says so: 170,773 under 999, 158,188 on the network proper; re-derived by edge type: 71,534 + 50,279 + 33,064 + 1,756 + 1,050 + 277 + 110 + 87 + 31). As written the count is wrong; it needs "outside the 999 codes" or 328,961.
- **[bug]** `research/fwa_downstream_queries.md:46` — "`blk_parents`, 136 MB, is read only by the build". `extras/mainflow_tree/sql/mainflow_tree.sql:92,99` and `qa_topology.sql:51,98,120` read `fwapg.blk_parents`. The main-flow tree is an input of `downstream_id`, so this is not incidental: see the next finding.
- **[fragile]** `research/fwa_downstream_queries.md:47,83` and comment30.md ("The `downstream_id` table builds in 142 s and takes 385 MB, but it needs the paths built first (16.5 min, 228 MB)") — the pointers are built "from the tree and the paths", but their cost is stated as the paths' build plus 142 s / 385 MB only. The main-flow tree (`fwa_stream_networks_mainflow_tree`, 482 MB per `env` log, built by `extras/mainflow_tree`, which itself rebuilds the paths and reads `blk_parents`) is also a prerequisite and is not counted. Either state that the tree is assumed already built (it is an existing extra, #2) or add it to the cost; the comment to the issue author in particular reads as the full price.
- **[bug]** comment30.md, "In those 24 the pointers are the better answer:" followed by "In 3, the tree and the paths take different lines and then rejoin." Nothing measured says which line is right in those 3 (`07_compare.sql:231-245` classes them only as "both walks end at the same segment"; `findings.md:203` likewise). The research file (line 83) is careful here (lists the 3 without calling them better); the comment over-claims. Say the pointers are better in 21 and differ by route in 3.
- **[fragile]** comment30.md, "The array walk depends on parallel workers, and a recursive CTE can't use them." The measurement supports "the pointer walk's plans use no workers" (no Gather in the P plans, `explain_20261021T171503Z.log` lines 199-253 and 457+; `ab` P ratios 0.90-1.01). That a recursive CTE *cannot* use workers is a general PostgreSQL claim nobody measured or cited (PG marks CTE scans parallel-restricted, but the non-recursive term is planned separately). The research file says "never uses them", which is what was measured; the public comment should say the same.
- **[bug]** comment30.md table header "Medians, random origins, to the outlet" with the 100,000-origin ltree cell "943 s": that cell is one run, no warm-up (`summary` "1 reps"; `bench_cells` L2 full 100000 repeats 1, warm f). The research table marks it "(one run)"; the comment drops the marker under a "Medians" header.
- **[fragile]** `research/fwa_downstream_queries.md:74,83` and comment30.md — "up to 3.7 times, BULK". 46,782 / 12,472 = **3.75** (`summary` P/A full BULK default); 3.7 is 1/0.27, the rounded ratio inverted. 3.75 or 3.8.
- **[fragile]** `research/fwa_downstream_queries.md:16` — "it returned the predicate's set less 1,495 such segments, and nothing else differed". Sets: holds (L1–L2 set diffs are only `absent_from_fwa_streams`, 1,495 / 86 origins). But order differed on 80 of the 100 origins (`diffs L1-L2 order code_tie_across_lines|1772 segments, 80 origins`). The next sentence names the cause (no unique key in `ORDER BY`), so this is wording: "nothing else in the set differed".
- **[fragile]** comment30.md — "which takes 15 s for one origin": the cell is 15,508 ms (research line 79 says 15.5 s). 16 s or 15.5 s.
- **[fragile]** comment30.md — "PR #PRNUM" placeholder must be filled before posting.

Everything else holds; full enumeration below.

## Enumeration

Mechanical pass: every sentence or table cell in the research file stating a number, ratio, comparison or quantifier
(grep for digits, `faster|slower|lead|even|same|agree|unchanged|every|each|all|none|never|only|about|up to`, then a
read of each section). **Research file: 107 claims** (sentences split at each independent number/comparison; table rows
grouped where one log line covers them). **comment30.md: 34 claims.** Verdicts: H = holds, W = wrong, U = unsupported, ~ = holds within rounding.

### research/fwa_downstream_queries.md

| # | line | claim | source | verdict |
|---|---|---|---|---|
| 1 | 3 | 4,907,441 segments | env: `fwa_stream_networks_sp|4907441 rows` | H |
| 2 | 15 | 4,000 comparison origins (1,000 random, 3,000 from three groups) | compare: `origins compared L2 full|4000`; bench_cells | H |
| 3 | 15 | about 1.4 times the segments (5.68 M against 4.00 M) | summary rows L2: 1,774,080+2,056,725+1,564,673+281,320 = 5,676,798; A: 1,155,537+1,668,889+1,010,973+168,932 = 4,004,331; ratio 1.418 | H |
| 4 | 15 | 1.65 M of the extra rows are side channels | compare `side_channel|1652256` | H |
| 5 | 15 | filtering to blue_line_key = watershed_key drops braids the water passes | class `path_through_side_channel` 1,919 / 702 | H |
| 6 | 15 | 1,242 distinct segment pairs = #3's shape | compare 1,242 = all L2–A order pairs; localcode_anomaly alone 1,208 | **W** |
| 7 | 15 | two lines sharing both codes → order by measure | class `code_tie_across_lines` 53 / 45 | H |
| 8 | 15 | 158,188 null local code on the network | DB: 328,961 null; 158,188 is non-999 subset | **W** |
| 9 | 15 | edge types 1450, 1100, 1350 mostly | DB: 71,534 / 50,279 / 33,064 of 158,188 | H (for the subset) |
| 10 | 15 | except on the origin's own line | findings:77 (criterion 1); class `code_999` all 47 segs null localcode, in A not L2 | H |
| 11 | 16 | fwa_streams lacks 369,217 segments | env `segments absent from fwa_streams|369217` | H |
| 12 | 16 | keeps only segments with a lookup row and an upstream-area row | `load/fwa_streams.sql:57-58` (left join lut, inner join upstream_area on lut's id) | H |
| 13 | 16 | on 100 origins, predicate's set less 1,495 | compare `origins compared L1 full|100`, `absent_from_fwa_streams|1495 segments, 86 origins` | H |
| 14 | 16 | nothing else differed | L1–L2 order diffs on 80 origins | **~ wording** (set only) |
| 15 | 16 | ORDER BY has no unique key, tied lines either order | `code_tie_across_lines` L1–L2 1,772 / 80 | H |
| 16 | 17 | array walk: distance on every segment | walk SQL; compare A distance assert | H |
| 17 | 17 | stops at a line with no path | class `path_ends` | H |
| 18 | 17 | drops the one parent segment at a code junction one below the mouth | `code_junction_below_node` 17 segs / 17 origins (one each) | H |
| 19 | 18 | pointer walk returns the same chain, same distances | 3,976/4,000 agree; max distance diff 0 m | H |
| 20 | 18 | continues where arrays stop at a pathless line on a tree node | `path_ends` A–P, A a prefix of P | H |
| 21 | 18 | keeps the segment the code junction drops | as #18 | H |
| 22 | 19 | A-pred = array set plus the segment starting at each junction | `junction_at_segment_start` 73 segs / 20 origins; the 20 origins have 75 path junctions | ~ (73 of 75) |
| 23 | 23 | 4,000 origins, every difference attributed, none left over | compare `assert: no unattributed difference|t` | H |
| 24-26 | 27-29 | A–P rows 3,077/4; 17/17; 21/3 | compare A-P lines | H |
| 27-35 | 30-37 | L2–A set rows 1,652,256/3,843; 19,743/15; 2,325/475; 1,919/702; 550/264; 94/20; 91/25; 47/23 | compare L2-A set lines | H |
| 36 | 37 | the 47/23 class label "null local code" | bench_diffs: all 47 have null localcode, none under 999 | H |
| 37-39 | 38-40 | order rows 43,320/3,688; 53/45; 9/9 | compare L2-A order lines | H |
| 40 | 42 | agree on 3,976 of 4,000 | 4,000 − `origins with a difference A-P|24` | H |
| 41 | 42 | largest distance difference where sets agree 0 m | compare `...(m) full|0` | H |
| 42 | 42 | both sum the same step_m | `03_walk_arrays.sql:115-117` vs `01_downstream_ids.sql:73` | H |
| 43 | 42 | Hope: both 239 segments, 161.40 km main flow, as docs give | compare hope A/P; `docs/03_functions.md:86` 161.40 | H |
| 44 | 42 | ltree 544 segments, 309.70 km; docs 308.54 stale | compare hope L2; docs:69; re-ran docs query: 309.70 | H |
| 45 | 46 | rebuilt in 992 s (16.5 min) | paths `wall 992 s` | H |
| 46 | 46 | blk_paths 228 MB with key | env `blk_paths ... total 228 MB` | H |
| 47 | 46 | blk_parents 136 MB | env | H |
| 48 | 46 | blk_parents read only by the build | read by `extras/mainflow_tree` | **W** |
| 49 | 46 | deterministic: md5s identical before/after | paths before/after md5 | H |
| 50 | 47 | 142 s, 385 MB (heap 280, key 105) | ids `build wall|141.9 s`, size line | H |
| 51 | 47 | the paths' 992 s comes first | — (omits the tree as a prerequisite) | **U (cost incomplete)** |
| 52 | 47 | every segment has a row | ids_qa assert one row per segment | H |
| 53 | 47 | node 4,547,628 | 4,483,174 + 64,454 | H |
| 54 | 47 | line 136,786 | 8 + 136,778 | H |
| 55 | 47 | junction 9,800 | 90 + 9,710 | H |
| 56 | 47 | null 213,227; 27,096 in tree | ids_qa roots | H |
| 57 | 47 | 26,690 + 23 + 383 | 27,096 − 23 (no_parent null) − 383 (dead_end null) | H |
| 58 | 47 | 186,131 off the tree | `method null, not in tree|186131` | H |
| 59 | 47 | sum = network | 4,547,628+136,786+9,800+213,227 = 4,907,441 | H |
| 60 | 47 | walk up from roots reaches every segment once | ids_qa assert | H |
| 61 | 47 | step_m definition, 1 cm; array walk the same expression | `01_downstream_ids.sql:73`, `03_walk_arrays.sql:116` | H |
| 62 | 48 | code indexes 1,923 MB | env: 425+503+450+545 | H |
| 63 | 52 | 16 cores, 128 GB, PG 17.5, shared_buffers 32 GB, work_mem 2 GB | env (4,194,304 × 8 kB; 2,097,152 kB; 17.5); cores/RAM from findings:71 | H |
| 64 | 52 | up to 8 workers | env `max_parallel_workers_per_gather|8` | H |
| 65 | 52 | medians of three after a warm-up; single origin median of 20 | summary "3 reps", "20 origins x 3"; bench.sh | H |
| 66 | 52 | ltree 100,000 and whole-group cells one run, no warm-up | bench_cells repeats 1, warm f (exactly those four) | H |
| 67 | 52 | no-origin statement 0.8 to 1.6 ms (55 ms A-pred) | summary 0-origin rows 0.80-1.64; A-pred 55.42 | H |
| 68-71 | 58 | 28 / 8 / 2.5 / 2.3 ms | 28.46 / 8.17 / 2.50 / 2.33 | H |
| 72-75 | 59 | 15 / 12 / 1.3 / 2.4 s | 14,697 / 12,272 / 1,261 / 2,381 | H |
| 76-78 | 60 | 102 / 9.2 / 6.1 s | 102,138 / 9,185 / 6,133 | H |
| 79-81 | 61 | 943 (one run) / 210 / 219 s | 943,398 (1 rep) / 210,496 / 218,587 | H |
| 82 | 63 | about 1,160 segments on the walks, 1,770 ltree | A per origin 1,156 / 1,165 / 1,147; L2 1,774 / 1,766 / 1,744 | H |
| 83 | 63 | 100,000 origins 115 M (174 M) | 114,689,634; 174,376,621 | H |
| 84 | 63 | 1 km about 5 segments an origin | 4,968 / 1,000 | H |
| 85 | 63 | 1 km arrays 42 ms, 2.6 s; pointers 19 ms, 1.5 s | 41.84; 2,631; 18.66; 1,512 | H |
| 86 | 63 | ADMS (10,458) 154 / 9.4 / 16 s | 153,614 / 9,437 / 16,120 | H |
| 87 | 63 | BULK (30,046) 199 / 12 / 47 s | 199,456 / 12,472 / 46,782 | H |
| 88 | 63 | LFRA (18,180) 101 / 1.7 / 2.7 s | 100,627 / 1,746 / 2,650 | H |
| 89 | 69-72 | ratio table 1.07; 0.53, 1.50, 0.96; 1.22, 1.25, 2.13; 0.59, 0.27, 0.66 | summary `ratio | A / P | full ... | default` | H |
| 90 | 74 | neither leads everywhere; arrays faster random 1,000 and whole groups; pointers random 10,000 and 1,000-samples | ratios; (list omits 1 origin, P by 1.07, and 100,000, A by 0.96; not claimed exhaustive) | H |
| 91 | 74 | up to 3.7 times, BULK | 46,782 / 12,472 = 3.75 | **W (rounding)** |
| 92 | 74 | up to 2.1 times, LFRA | 394 / 185 = 2.13 | H |
| 93 | 75 | 1 km pointer 1.7 to 5.5 times faster on each batch, both passes | 1 km ratios 1.74-5.50, all 14 > 1 | H |
| 94 | 76 | both faster than ltree join on each batch at defaults; arrays 3.3 at one, 4.5-58 batches; pointers 3.5, 4.3-47; random 1,000 9.7 and 5.2 | L2/A default 3.27, batches min 4.48 max 57.62; L2/P 3.51, min 4.26 max 46.64; 9.73, 5.15 (12,272/2,381 = 5.154) | H |
| 95 | 77 | 11 interleaved cells; P control 0.90-1.01; arrays 1.5 / 1.7 / 7.6; BULK 101 s vs 52 s; trace 2; ltree slowed 1.6 / 1.15; 1 km unchanged (on those cells) | 11 `ab` lines; 1.52, 1.72, 7.61; 100,806 / 52,482; 1.95; 1/0.61 = 1.647, 1/0.87 = 1.151; A 1 km 0.99, P 1 km 1.01 | H |
| 96 | 77 | at one origin the two passes give the same times for every method | 1-origin rows: largest gap L2 8.17 vs 8.42 (3 %) | ~ |
| 97 | 78 | per origin arrays 0.9 → 2.1, pointers 0.6 → 2.2 ms; join 9 to 10 ms | 0.919 → 2.105; 0.613 → 2.186; L2 10.214 / 9.434 | H |
| 98 | 79 | A-pred 15.5 s one origin; evaluated on every segment; 1,000 time out at 30 min | 15,508 ms; explain: seq scan 4,907,441 rows, join filter removed 4,907,280; bench.sh `statement_timeout` 30min; summary "timeout" | H |
| 99 | 83 | arrays faster random 1,000 and whole groups (up to 3.7) | 3.75 | **W (rounding)** |
| 100 | 83 | pointers random 10,000, 1,000-samples (up to 2.1); 1 km 1.7-5.5 on each batch | as #92, #93 | H |
| 101 | 83 | without workers, interleaved: even at random 1,000; pointers 2.4 at 10,000, 1.9 on BULK | ab A 1,948.3 vs P 1,971.9; 15,562.2 / 6,592.6 = 2.36; 100,806.4 / 52,482.2 = 1.92 | H |
| 102 | 83 | agree 3,976 of 4,000; of 24: 17, 4, 3 | bench_diffs A-P distinct origins per class 17/4/3, total distinct 24 (disjoint) | H |
| 103 | 83 | cost the paths' build plus 142 s / 385 MB against 228 MB | omits the main-flow tree prerequisite | **U** |
| 104 | 83 | simpler query (no window over the rows) | windows in `03_walk_arrays.sql:85,130,176`; none in `04_walk_pointer.sql` | H |
| 105 | 85 | 9.7 times at random 1,000; 12.0 interleaved; 4.8 without workers | 9.73; 15,493.6/1,285.8 = 12.05; 9,405.7/1,948.3 = 4.83 | H |
| 106 | 85 | unnests about four junctions an origin | per random origin with a path, mean `cardinality(path_blks)` 3.81 (env's 4.18 is per blue line) | H |
| 107 | 85 | blk_on_or_upstream in ON reads every segment for each origin | explain (as #98) | H |

(Grouped rows 24-39, 68-81 and 89 were checked cell by cell.)

### comment30.md

| # | claim | source | verdict |
|---|---|---|---|
| C1 | #34 measured questions 2 and 3 of #30 | #30 body (q2 downstream_id, q3 array vs ltree) | H |
| C2 | PR #PRNUM | placeholder | **fill before posting** |
| C3 | one machine, full provincial load, 16 cores, PG 17.5, warm cache | env; findings:71 | H |
| C4 | downstream_id built from the tree's node matches and the paths, walked with a recursive CTE | ids SQL (also line steps) | H |
| C5 | "Medians" over the table | 943 s cell is 1 run | **W** |
| C6-C20 | the 15 table cells | as research #68-81 | H |
| C21 | arrays faster random 1,000 and whole groups, up to 3.7 | 3.75 | **W (rounding)** |
| C22 | pointers faster 10,000 and each 1,000-sample, up to 2.1 | 2.13 | H |
| C23 | 1 km pointers 1.7-5.5 faster on every batch we ran | 14 ratios 1.74-5.50 | H |
| C24 | array walk depends on workers | ab A 1.52 / 1.72 / 7.61 | H |
| C25 | a recursive CTE can't use them | measured only: P plans have no Gather | **U** |
| C26 | 11 cells interleaved; even at 1,000; 2.4 at 10,000; BULK 1.9, 52 s vs 101 s; BULK a Skeena group | ab lines; Bulkley drains to the Skeena | H |
| C27 | same segments, order, distances for all but 24 of 4,000 | compare: A-P diffs only `set`, 24 origins; distance max 0 | H |
| C28 | "In those 24 the pointers are the better answer" | 17 + 4 supported; 3 `route_differs` not judged | **U** |
| C29 | 17 / 4 / 3 | as research #102 | H |
| C30 | 142 s, 385 MB; needs the paths first (16.5 min, 228 MB) | ids, paths, env; omits the tree | **U (cost incomplete)** |
| C31 | both walks faster than the join on every batch; arrays 9.7 at 1,000, 4.5-58; workers slowed the join 1.15-1.6 on re-run cells; about four junctions an origin | as research #94, #95, #106 | H |
| C32 | about 1.4 times the segments, mostly side channels; ordered by codes fails where local codes out of order (#3) | as research #3, #4; #3 title | H |
| C33 | blk_on_or_upstream evaluated on every segment; "15 s" one origin; 1,000 don't finish in 30 min | explain; 15,508 ms → 15.5/16 s | **~ (15 s rounding)** |
| C34 | docs 308.54 stale, documented query returns 309.70, 161.40 holds; fwa_streams lacks 369,217; ORDER BY no unique key | docs:69,86; re-ran docs query 309.70; env | H |

Public-text scan of the research file and comment30.md: no hosts, credentials, private repos or home paths. The leak is in a committed log (first finding).
