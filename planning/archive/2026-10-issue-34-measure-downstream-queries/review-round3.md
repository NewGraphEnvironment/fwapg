# Review round 3 (#34)

Scope: `planning/active/scripts/bench.sh` (the ab step), `07_compare.sql` class predicates, `08_summary.sql`, and every comparative or quantified claim in `research/fwa_downstream_queries.md`, `findings.md` "Phase 3: timings" and "Phase 4: correctness", and the Answers to #30. Each claim was checked against `logs/summary_20261021T231626Z.log` (rows, `ratio` and `ab` lines) and `logs/compare_20261021T231634Z.log`, with read-only SELECTs where noted.

## The mechanism

The round-2 audit ("Claims checked") checked each claim **as the checker re-stated it**, against **one source the checker picked**. It did not check the sentence as written against every row its quantifier covers. The table's claim column adds scope that the research text does not carry ("with workers", "`ratio L2 / A full 1000`" meaning random). A claim about running without workers was checked against the default `ratio` lines, or not checked at all. The settings claims were generalised from the eleven `ab` cells to "the array walk", "the shipped trace" and "the ltree join" without a look at the batches the `ab` run did not cover. The enumeration also covered only the research file, so round 2's own instance in `findings.md:146` is still there. The fix is the same for every instance below: take each sentence as written, list the rows its quantifier and scope cover (all batches, both settings, or whatever the sentence names), and either show them or narrow the sentence.

## Findings

- **[bug: wrong conclusion] `research/fwa_downstream_queries.md:73`: "without workers the arrays lose their lead on large batches" and "a `downstream_id` is cheap to add … if a consumer … runs without workers".** Without workers, the arrays lead or tie on most multi-origin batches, read off the same pass's `ratio A / P … noparallel` lines:
  - random 1,000: 0.77 (`ab`: 1.95 s against 1.97 s, 0.99)
  - ADMS_1000 0.97, BULK_1000 0.85 and LFRA_1000 0.85
  - LFRA whole (18,180 origins, a large batch) 0.83
  - ADMS whole 1.04

  The pointers lead without workers only at random 10,000 (2.22; `ab` 2.36), at 100,000 (1.78) and on BULK (2.06). So "large batches" fails on LFRA, and the recommendation "runs without workers" points the wrong way for every 1,000-origin batch. The claims table has no row for either sentence. Its "who leads where" row was checked against the default lines only.

- **[bug: wrong conclusion] `research:67` ("Workers … they speed the array walk") and `research:64` ("the pointers [lead] … on each group's 1,000-origin sample").** The `ab` run covered no group-subsample cell. On those cells the main table shows workers slowing the array walk well beyond the drift the control shows in the same slots:
  - A, default against no-parallel: LFRA_1000 394 against 149 ms (2.6 times slower with workers), BULK_1000 1,322 against 869 (1.5), ADMS_1000 1,873 against 1,363 (1.4).
  - P in the adjacent cells moved 1.06, 1.04 and 1.10. For example `cell_A_full_LFRA_1000_*` ran at 19:04/21:05 and `cell_P_full_LFRA_1000_*` at 19:04/21:05.

  So the pointers lead on the subsamples (1.22 to 2.13) only because workers hurt the array walk there. That is a settings effect the research attributes to the methods, and it contradicts the unscoped "workers speed the array walk". Re-run those three cells through `bench.sh ab`, or scope both sentences to the cells measured.

- **[fragile: unscoped generalisation] `research:67`: "they speed the shipped trace 2 times; they slow the ltree join 1.15 to 1.6 times".**
  - Both come from random 1,000 and 10,000 only (findings:170 scopes them; the research does not).
  - At one origin, which is how `fwa_downstreamtrace` is called, workers do nothing. L1 28.46 against 28.12 ms and L2 8.17 against 8.42 ms, from the single-origin re-runs a minute apart (`cell_L1_full_1_*_20261021T2126*`/`2127*`).
  - On whole groups the main table points the other way for L2: BULK 199 against 216 s and LFRA 101 against 137 s, faster with workers, while P's control moved 0.96 and 0.89. Those are single runs, so they are weak evidence, but "slow the ltree join" is stated with no scope.
  - Likewise "speed the array walk 1.5 to 1.7 times on random batches" is 1.00 at one origin (2.50 against 2.50 ms).

- **[fragile: one fact derived twice] `research:64` and `findings:168` give different A/P ranges for the same claim.**
  - The research gives "0.27 … to 2.1" with no setting named, and the claims table re-states it as "with workers".
  - findings:168 gives "0.27 … to 2.22 (random 10,000 without workers)".
  - The `ab` run gives 2.36 without workers at 10,000.

  A reader of research:64 next to research:73 (which talks about running without workers) takes 2.1 as the range over both settings. Name the setting in the sentence, or use the full range.

- **[fragile: one fact derived twice] `research:75`: "5.8 to 9.7 times faster than the ltree join at 1,000 origins (without and with workers)".**
  - This is the with/without contrast taken from the main table's no-parallel column, which the accepted caveat says is confounded with time.
  - The interleaved run measured the same pair: L2/A 15.49/1.29 = 12.0 with workers and 9.41/1.95 = 4.8 without. L2 at 1,000 moved 26 % between the runs (12.3 s against 15.5 s).
  - "At 1,000 origins" also means random 1,000 only: the group subsamples give 6.9 to 50.
  - The same applies to research:66's "9.7 and 5.2 times at 1,000 random origins" (interleaved: 12.0 and 7.1).

- **[fragile: method text contradicts the data behind ranges] `research:51`: "Medians of three repeats after a warm-up".** Not true for L2's 100,000 and whole-group cells, which ran once with no warm-up (accepted as method, but the research never says so). Those single runs set the endpoints of research:66's ranges: L2/A 1.75 is L2 no-parallel at 100,000 (one run), and 58 is L2 on LFRA whole (one run). L2/P 3.1 is L2 no-parallel at 100,000 too. The 943 s, 154 s, 199 s and 101 s in the speed text are the same single runs.

- **[bug: round-2 finding not fixed] `findings.md:146`: "Each group's seeded 1,000 sits in the same order".** This is the sentence round 2 flagged, still unchanged. With workers, the whole groups order A < P < L2 and the subsamples order P < A < L2. The claims audit missed it because it enumerated only the research file.

- **[bug: wrong cause] `findings.md:235`: "L1's main flow is 0.32 km shorter because its trace cuts the origin's segment at the measure; its total is lower for that and for the 8 segments absent from `fwa_streams`".**
  - The Hope fixture sums `ST_Length` of whole `fwa_stream_networks_sp` segments joined by id (07_compare.sql:601-609), so the trace's cut never enters the sum.
  - Measured: L2 returns 8 segments that L1 does not, all absent from `fwa_streams`. Two are main flow, 701242814 (183 m) and 701242858 (141 m), which make up 324 m = the 0.32 km. All eight sum to 1,892 m, which is the whole 309.70 − 307.81 km gap.
  - So both differences are the absent segments. The cut plays no part.

- **[fragile: quantifier] `findings.md:148`: "P … differed by 12–39 % between them".**
  - P's default-against-no-parallel ratio in the main table runs from 0.77 (1 km BULK_1000, the other direction) through 0.89 to 0.96 on the whole groups, to 1.02 to 1.06 on several cells, and up to 1.39.
  - 12 to 39 % is the random-batch subset only. The case for the re-run still stands.

- **[fragile: quantifier] `findings.md:224`: the local-code predicate "flags … every set difference it explains".** Six of the 550 `localcode_anomaly` set differences (5 segments of one origin with A only, 1 segment with L2 only) are attributed by the origin branch (07_compare.sql:397-406), not by the segment predicate whose base rate is quoted. That branch attributes any chain-line segment of an anomalous origin, whatever the segment's own codes. So the base-rate argument covers 544, not 550.

- **[fragile: incomplete table] `research:27-39`: the correctness table omits the L2–A order class `path_through_side_channel` (9 segments, 9 origins), while research:25 says every order difference was attributed.** The rows sum to 43,373, not the logged 43,382.
  - The class (07_compare.sql:489-494) attributes any order difference where either segment is off a main line.
  - On all 9 rows the earlier segment is a side channel's lowest segment (measure 0) and the later one is a main-stem segment below its rejoin, carrying a higher local code (for example 400.431358.782660 then 400.431358.782709). The label fits these rows, but the predicate would accept any side-channel pair.

## Checked and holding

- **07_compare.sql `path_ends`:** for every origin in A–P, A–P 1 km, L2–A and L2–P `path_ends`, the chain's last line (the last element of `path_blks`, or the origin's own line) has no `blk_paths` row. 11 of the 15 L2–A origins are also P-terminal (the L2–P `path_ends` count is the same), which fits "the paths stop" plus water leaving BC.
- **"About four junctions an origin" (research:75):** the claims table's evidence is a proxy, the per-line mean 4.18 over `blk_paths`. Per origin: random 1..1,000 3.76 (3.93 over origins that have a path), BULK 3.83, LFRA 3.03, ADMS 6.18. So the claim holds for random origins.
- **Holding against the log:**
  - the 1.4 times (5,676,798 / 4,004,331)
  - 1.65 M side channels
  - 1,242 pairs
  - 3,976 of 4,000, with 17 + 4 + 3 = 24 disjoint
  - the pointer method counts and their sums (4,907,441)
  - 1,923 MB
  - the speed table cells
  - the 1 km figures
  - L2/A 1.75 to 58 and L2/P 3.1 to 47 (the min and max over both settings)
  - A/P at 1 km 1.74 to 5.50
  - the per-origin 10,000 to 100,000 figures
  - the Hope rows
- **bench.sh `ab`:**
  - The four runs per cell set workers correctly (`noparallel*` glob; each run is its own session).
  - All 44 logs are present.
  - 08's `ab` lines take the median of six repeats per setting, with the warm-up excluded.
  - Each run replaces only its own `settings` rows.
  - P's control runs in a different window from A's (for example `A BULK` 22:47–23:01, `P BULK` 23:02–23:12), so it shows drift in that window, not in A's. A B B A on A itself is what cancels linear drift.
  - No defect.
