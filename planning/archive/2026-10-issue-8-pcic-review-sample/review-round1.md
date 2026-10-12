# Review round 1: branch 8-pcic-crosswalk-visual-review-of-a-sample vs newgraph (extras/)

## Findings

- **[severity: bug (data loss)]** extras/pcic_crosswalk/review_build.sh:52 (with the guard at 34-38). `rm -f "$GPKG"` deletes `data/review/review.gpkg` every time the script runs. The design guard above it only stops a *different* draw. When the build and seed are unchanged the draw is the same, `cmp` passes, and the guard lets the `rm` go ahead. The README tells the reviewer to fill that same file in place and score it there: "Score the filled-in GeoPackage with `./review_score.sh data/review/review.gpkg`". So any re-run deletes every verdict, confidence and note entered so far, with no warning. A re-run is easy to trigger: regenerating `flags.csv`, re-checking after `qa_gauges.sh`, or simply running the build twice. If QGIS has the file open at the time, the file is also deleted and recreated underneath it. Suggested fix: refuse to overwrite an existing `$GPKG` unless its `review` layer has no non-blank verdict, confidence or note (or unless a flag such as `--force` is given), or build to a temp path and refuse to replace a file that holds any filled row.

Everything else checked out. These were verified directly, not assumed:

- `review_test.sh`, run in a temp copy: all 13 checks pass.
- I filled a copy of the real `data/review/review.gpkg` through GDAL, including a note containing a comma, quotes and a newline. It scored correctly: 60/12/12/12/12/12 drawn, and the Wilson bounds are sane at p=0.
- Blinding:
  - The GeoPackage's field names carry no `subid`, stratum, rank or flag.
  - The feature order of `fwa_candidates` within each `review_id` does not track `candidate_rank`. Rank 1 is first in 40 of the 106 outlets with several candidates, which is what chance gives.
  - The only stratum anyone can see is `unplaced`: those outlets have no `fwa_placed` point. That is inherent to the task.
- Renaming `pcic_outlets` and `pcic_candidates` to `pcic_qa_*` leaves `pcic_outlets_pkey` and the other index names attached to the renamed tables. On the next run Postgres picks non-conflicting names (tested with a temp table: `a_pkey1`). The unnamed `CREATE INDEX ON` calls in 00 and 02 do the same, so a re-run does not fail.
- `blk_paths.path_blks[1]` is the line's parent, as `review_sample.sql`'s junction logic assumes (`blue_line_paths.sql:250`).
- Every row of `fwapg.pcic_qa_flow` (37,667) is a placed outlet. The strata in `pcic_review_strata` have no duplicate `(subid, stratum)` rows, so the design table has no duplicate rows.
