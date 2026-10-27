# Code-check round 1: #24 diversions (ce4add3...HEAD)

## Checklist read

- code-check-infra.md: in full.
- code-check-python.md: in full.
- code-check.md: the prose of all 14 H3s under `## Mechanisms`, `|` table rows skipped. I read no section outside Mechanisms beyond the index lines.
- code-check-shell.md: I read 6 headings: "psql does not interpolate `:'var'` inside a dollar-quoted string, and `\quit N` exits 0", "A heredoc whose body contains its own delimiter ends early", "`mktemp` template needs enough X's", "A second `trap … EXIT` replaces the first", "Heredoc precedence in pipelines", "Quoting". The rest I skipped, judged from the index.
- code-check-r.md: I read 2 headings: "Postgres row order is never fixed unless the query fixes it", "A value compared as `::text` in SQL has PostgreSQL's spelling". The rest I skipped, judged from the index (R language, packages, DBI).
- code-check-spatial.md: I read 3 headings: "FWA `upstream_route_measure` misses the next segment's start", "FWA main flow is not edge type 1000 alone", "A Freshwater Atlas main stem's downstream end lies on the receiving river's centreline". The rest I skipped, judged from the index (terra, sf, GDAL, bcdata).

## Clean

No issues found.

What I checked, so the next round can see what this one covered:

- **Flow and area stay consistent across 06, 06_daily, 07 and 09.**
  - The diversion's flow reaches its receiving outlet R through `fwa_parent_subid` in 06_daily.
  - In 07, the `FILTER (c.fwa_parent_subid = s.subid)` drops the diversion from the position parent P's segments, and the CASE adds it only on R's own segment.
  - So R's segment equals R's `q_acc`, and P's segments neither carry its flow nor keep its area: P's `local_area_ha` and 07's share both subtract it.
  - In 06's area CTE, `coalesce(position_parent, fwa_parent)` means the diversion is not subtracted from R.
  - Double counting: guard 2 in 06 (`position_parent = anchor`) is the only shape that could count the flow twice. I worked through the cases where R lies downstream of P on the FWA, or the reverse, and found no double count. A cycle is caught by the existing `fwa_depth` check.
- **An empty FILTER aggregate does not leave a NULL in `upstream_subids`.** On a segment with no qualifying child, the FILTER aggregate is NULL, and `NULL || '{}'` is `array_cat`, which gives `'{}'`. I checked this read-only against the DB. The published `pcic.segment_weights` has 0 NULL `upstream_subids` out of 3,377,037.
- **The guards in 03 and 06 fail loudly, not toward pass.**
  - Each LEFT JOIN guard catches an absent row (a NULL exit, a missing crosswalk row).
  - 03's exit exclusions mirror `pcic_crosswalk02_candidates.sql` (lines 55-60).
  - Guard 3's ownership order `(downstream_route_measure, depth, subid)` on one `linear_feature_id` matches 07's step-0 order and qa.sql's `DISTINCT ON`.
- **Position at the exit vertex.** The diversion sits exactly on the exit segment's `downstream_route_measure`, the upper of the two segments sharing that vertex, as 02 places outlets. 06 and 07's step > 0 rule (`seg_measure < measure - 0.001`) send a line joining at that vertex below it. A PCIC child of the diversion joining there would be caught by the existing qa test "no placed outlet sits above a confluence", because 06 never moves a diversion.
- **The new qa tests fail on no rows or NULL.**
  - Each one either requires `count(*) > 0` or wraps its subqueries in `coalesce(..., false)`. A scalar subquery returning several rows errors under `ON_ERROR_STOP`.
  - The recursive CTE in "every diversion is placed" ends on NULL when there is no placed ancestor, so the test fails.
- **pcic_crosswalk.sh**
  - `cp -R sql` copies the new file into `$CODE`.
  - Every reader of `fwapg.pcic_diversions` (qa.sql, qa_report.sql, and days_build.sh by way of 06_daily, which does not read it) runs before the rename on line 500.
  - A failed QA keeps the table, and the next run's 03 drops and recreates it.
  - `review_build.sh`, `qa_gauges.sh` and `pcic_test.sh` do not reference it. `pcic_test.sh` runs only 06_daily, which does not read the diversions table.
- **Per-year days reuse.** A diversion change moves `fwa_parent_subid`, so `CROSSWALK_MD5` changes and each per-year file is rebuilt.
- **Shell and psql traps.**
  - The new DO blocks interpolate no psql variables.
  - Both heredocs in mutation_checks.sh are quoted (`<<'PY'`), and none contains its own delimiter.
  - `mktemp` uses `XXXXXX`, and there is one EXIT trap.

Two non-blocking notes, outside the findings:

- `planning/active/logs/mutation_checks.sh` M5: its round loop has no "did not converge" check, unlike the job's line 322. Measured: under `set -e`, bash 3.2 and 5 both carry on past a loop whose last `[ ] && break` is false. If placement ran 10 rounds without converging, M5 would report the round-10 state without saying so. It only affects the measurement script.
- `research/pcic_routed_flow_periods.md:30` describes `upstream_subids` as "the placed outlets directly above it". A diversion now also appears in its receiving outlet's segment. The routing formula is unchanged, so no consumer breaks, but that sentence is now out of date.
