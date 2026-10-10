# Code check, round 3: fwapg#7 drainage check (staged diff)

Scope: `git diff --cached`. I read qa_drainage.sql (new), qa.sql, pcic_crosswalk.sh, README.md, planning/active/*.md, review-round1.md and review-round2.md in full. I read the checklist in full: the general mechanisms, shell, infra (Docker/Postgres), and the spatial file, which has nothing that applies to this SQL. All DB queries ran with `default_transaction_read_only=on`.

## Mechanism and enumeration

**The mechanism behind R1's first finding is "a guard that fails toward pass".** A state that could not be measured was folded into the state that means "measured and fine". A NULL ratio matched neither CASE arm, so it fell through to the implicit ELSE. The ELSE is NULL, which the report calls `ok` and the ceiling counts as "not flagged". The checklist remedy is to treat unreadable as a third state, give it a name, assert on it, and enumerate the complement, so every outcome is a deliberate resting place. The `unmeasured` label did that, but only for NULL. The same collapse happens when a missing measurement is written as a *valid value* (a `0`) rather than as NULL: a null check cannot see that by construction (two earlier checklist rows).

Every test, filter or CASE in the diff whose NULL, empty or missing outcome could read as a pass:

| # | Site | NULL / empty / missing outcome | Safe? |
|---|---|---|---|
| 1 | qa_drainage.sql:50 `sum(coalesce(ST_Length(r.geom), 0))` | When no river rows join a subtree, length becomes **0**, not NULL. The density ratio is then 0: the `big` arm can never fire, and `small` falls back to runoff alone. | **No** (Finding 1). It is live on 83 outlets. If the whole `pcic_rivers` table is lost, every length is 0, the median is 0, `nullif` returns NULL and every outlet is `unmeasured`, so the test fails. That part is safe. |
| 2 | :55, :78 `pcic_flow` INNER JOIN | An outlet with no monthly rows is dropped from the table, not flagged. An empty table gives 0 rows, which fails the `main_stem > 0` floor. An all-NULL avg makes the ratio NULL, which is `unmeasured`. | Safe today. `04_select` places only outlets that have a series. I checked: 37,667 table rows = 37,667 placed. The file does not enforce this itself. |
| 3 | :77 `pcic_length` INNER JOIN | `up` seeds every outlet, so no row can be dropped. | Safe |
| 4 | :76 `fwa_stream_networks_sp` INNER JOIN | Placements come from candidates on that table. | Safe (same reconciliation as #2) |
| 5 | :57-61, :79 `area` LEFT JOIN | A missing lut or area row, a NULL area or a 0 area gives a NULL ratio, which is `unmeasured` and fails the test. A missing table raises ERROR, which aborts the job. Lut fan-out makes `ADD PRIMARY KEY` fail loudly. | Safe |
| 6 | :82 `WHERE x.flag IS NULL` ("placed" means no flag) | This is the same predicate qa.sql and the README use. | Safe |
| 7 | :67 `main_stem` = `blue_line_key = watershed_key` | A NULL `main_stem` skips `NOT main_stem`, still gets a flag, drops out of the medians and the `> 0` floor, and is labelled "side channel" in the report. | Safe. 0 NULL keys in `fwa_stream_networks_sp`. |
| 8 | :121 `WHEN NOT main_stem THEN NULL` (the side-channel exemption) | The exempt population has no bound. The `count(*) FILTER (WHERE main_stem) > 0` floor catches only the case where every row is exempt. | Safe as designed and documented: 627 exempt (1.7%). A regression that pushed placements onto side channels would leave this test blind, but the >10x-flow ceiling covers that class independently. |
| 9 | :86-95 `regional` / `province` medians | A NULL or 0 median gives NULL through `nullif`, which is `unmeasured`. A missing group gives NULL `r.n`, so `WHEN NULL >= 20` takes ELSE, the province median. | Safe |
| 10 | :103-107 `nullif` on area and median | A divisor of 0 gives NULL, which is `unmeasured`. NaN cannot arise, and in any case NaN sorts above 5 in PG, so it would read `big`, not pass. | Safe |
| 11 | :124-126 CASE order and the implicit ELSE (`ok`) | `unmeasured` comes before `small` and `big`, and the two are mutually exclusive. ELSE is reached only with two finite, non-NULL ratios, *except* site #1, where a ratio is 0 by construction. | Safe apart from #1 |
| 12 | :124 rounded vs unrounded ratios | The CASE reads the input columns, which are unrounded; the CSV shows them rounded. A boundary row re-derived from the CSV can disagree with its flag, but never toward pass. | Safe |
| 13 | qa.sql:128-133 ceiling test | Every term is a `count(*)` comparison, so the result is never NULL. An empty table makes `> 0` false. A missing table makes psql ERROR, `qa=$(...)` returns non-zero, and `set -e` exits before export. | Safe |
| 14 | pcic_crosswalk.sh:166-167, 171-173 | qa_drainage.sql runs under `ON_ERROR_STOP` and `set -e` right before qa.sql, so qa.sql cannot read a stale table in the pipeline. The new test name has no `\|`, so the `'\|t$'` parse holds. | Safe in the pipeline. `fwapg.pcic_qa_drainage` is not in the cleanup DROP (line 181), so it outlives the run, and a hand-run qa.sql can read the previous build's table. README step 7 ("drops the `fwapg.pcic_*` staging tables") overstates. Not a pass path in the job. |
| 15 | Group-median normalisation (not a NULL path) | A defect that shifts most of a group moves the median the group is judged by. | Accepted design (R1 note, province fallback). Seeded 200/200 still trips the ceiling. |

## Findings

- **[severity: fragile]** extras/pcic_crosswalk/sql/qa_drainage.sql:50 (with :103-107 and :124-126). **This is the R1 mechanism again, one axis over: the fix covered NULL, and this missing measurement arrives as 0.** `coalesce(ST_Length(r.geom), 0)` turns "this subtree has no PCIC river at all" into a length of 0. Without the coalesce, `sum()` over all-NULL rows would return NULL. Effects:
  - The density ratio is exactly 0. Since `big` needs `density_ratio > 5`, the `big` arm is unreachable for these outlets.
  - Since `0 < 0.2` always holds, "both legs agree" falls back to runoff alone for `small`.
  - The outlets are labelled `ok` (flag NULL) in the table, the CSV and the report.

  I checked the DB: **83** main-stem outlets have `pcic_length_km = 0`. All 83 are PCIC lake sub-basins with nothing upstream, i.e. headwater lakes with no river geometry. **2** of them exceed 5x on the runoff leg, the only leg that can measure them, and read `ok`:
  - 3007696 (STHM, edge 1450): runoff ratio **274.7** (0.049 m³/s on 0.04 km²)
  - 8013929 (KEEC): runoff ratio 5.96

  2 others are flagged `small` on runoff alone. So the review list for #8 silently drops a whole class from `big`, and the `unmeasured` guard cannot see it because the ratio is not NULL. The ceiling test is not at risk: these would add at most 2 to `big`, giving 126, under 200.

  **Fix.** Give this case its own resting place rather than letting it fall into ELSE. For example, ahead of the small/big arms:

  ```sql
  WHEN pcic_length_km = 0 THEN CASE WHEN runoff_ratio < 0.2 THEN 'small' WHEN runoff_ratio > 5 THEN 'big' ELSE 'runoff only' END
  ```

  Alternatively, a separate `'not checked (lake headwater)'` label, counted in the report. Either way, do not make it `unmeasured`: those 83 rows would fail the test on healthy data. The header comment's "reads low on short subtrees" should say that zero-length (lake-only) subtrees are judged by runoff alone, or not at all.

No other findings. The counts in the header, qa.sql, README and findings.md (218 small, 124 big, 37,040 main stem, 0 unmeasured) match the DB.
