# Code review, round 4 (fwapg#8 branch, extras/pcic_crosswalk)

Probes ran in a scratch copy (`$SCRATCH/r4`) and against the database through TEMP tables only.
No repository file and no persistent table was modified.

## 1. The round-3 table, row by row

| place | claim | verdict |
|---|---|---|
| `data/review/review.gpkg` (replaced) | `guard_live` runs before the build and before the `mv` | **confirmed**. It is called at review_build.sh:77 and :173, and the `mv` is at :174. `guard_live` is a plain function call, not a subshell, pipeline or `if`/`||` operand, so the `exit 1` calls at :60, :65, :68 and :74 end the script. Probed: `lsof -- file` exits 0 while a process holds the file open and 1 when nothing does, so the `--` does not silently turn the check off. `ogrinfo -sql` leaves the GeoPackage's md5 unchanged. |
| its `-wal`, `-shm` and `-journal` | refused whether or not the GeoPackage exists | **confirmed**. The loop at :59-61 runs before the `[ -e "$GPKG" ] \|\| return 0` at :62. |
| `review.building.gpkg` and `*.building.csv` | script-owned names | **confirmed**. They are `rm -f`'d with the building file's sidecars at :86. |
| `review/sample_design.csv` | `cmp` refuses a new draw, and the file is written only on success | **confirmed**. The `cmp` is at :91-94 and the `cp` at :176, after the second `guard_live`. |
| `data/review/sample_design.csv` and `flags.csv` | written only on success | **confirmed for a failed build** (:175 and :177). **Incomplete for a successful new draw.** See finding 2. |
| `fwapg.pcic_review_*` | script-owned | **confirmed**. They are created with `DROP IF EXISTS` or `-overwrite`. |
| crosswalk against `pcic_qa_outlets` and `pcic_qa_candidates` | the staging guard plus the cross-build invariant | **confirmed for what it compares, wrong as the comment at :32-34 states it.** The invariant checks only that the crosswalk's rank and blue line sit among the local candidates. Two builds that share candidates pass it however differently they placed. See finding 1. |
| `pcic_qa_drainage`, `following` and `flow` | written by the job with the crosswalk; a failed run leaves the staging tables | **wrong for the `load.sh` route.** The claim holds for a failed job, which the :36 guard catches. `load.sh` (`load/pcic_fwa_crosswalk.sql`) truncates and reloads the crosswalk and leaves these three tables alone. Nothing compares them with the crosswalk, and the invariant passes. See finding 1. |
| `pcic_qa_gauges` | the job drops it (pcic_crosswalk.sh:17) and `review_build.sh` requires it (:36) | **confirmed for the job route, wrong for the `load.sh` route.** `load.sh` also replaces `fwa_stream_networks_discharge_monthly`, which `qa_gauges.sql` reads at :68 and :129. It does not drop `pcic_qa_gauges`, so gauge flags computed on the local discharge survive under a published crosswalk. |
| `data/rivers.geojson` and `lakes.geojson` | not guarded, accepted | accepted, not re-flagged |
| `blk_paths` | built from the FWA alone and rebuilt inside the job | **confirmed**. It is rebuilt at pcic_crosswalk.sh:137 in one transaction (`blue_line_paths.sh -1`). |
| `review_score.sh` and `review_test.sh` | write only inside `mktemp -d`; the md5 ties the GeoPackage to its design | **confirmed**. Both write only under `$T`. `review_score.sh` refuses at :223-229 when the sample_id is not the md5 of the design. |

## 2. Places the mechanism reaches that the table is missing

- **The `load.sh` route for every local QA table, not just the crosswalk row.** `load.sh` and
  `psql -f load/pcic_fwa_crosswalk.sql` replace the crosswalk and the discharge table, and leave
  `pcic_qa_drainage`, `_following`, `_flow`, `_gauges`, `_outlets` and `_candidates` in place.
  The table credits the invariant with covering this route. The invariant only covers candidates,
  and candidates do not change with placement logic (crosswalk04 to 06), so this route is open.
  This is finding 1.
- **`data/review/flags.csv` after a successful *new* draw.** The refusal messages at :73 and :92
  name only `review.gpkg` and `review/sample_design.csv`. The flags file is then replaced, and it
  carries no `sample_id`. This is finding 2.
- **`data/qa_drainage.csv` and `data/qa_following.csv`** (pcic_crosswalk.sh:171 and :174) are
  written before QA, so a failed run leaves them describing that run. **`data/qa_gauges.csv`**
  outlives the `DROP` of `pcic_qa_gauges`. No script reads any of the three (grep), so none can
  produce a wrong review. I mention them only because round 3 used the mtime of
  `qa_gauges.csv` as evidence, and these files carry no build provenance.

## 3. Round 3's fixes

- **Staging check (:36).** If `psql` fails, its empty output is not `t`, so the script refuses.
  That is correct.
- **Cross-build invariant (:40-47).** If either table is missing, or `psql` fails, `mismatch`
  is empty and the script refuses. It does **not** refuse a legitimate build where an outlet was
  moved below a junction:
  - `pcic_crosswalk06_subbasins.sql:41-49` never changes `blue_line_key`. It moves the outlet
    along its own line.
  - Where the move is more than 1 m, it clears `candidate_rank`, and the invariant skips rows
    with a NULL rank.
  - Where the move is 1 m or less, the rank is kept, and the candidate row still has the same
    `blue_line_key`.

  Its weakness is reach, not direction. See finding 1.
- **`guard_live`, called a second time at :173.** The window before the `mv` is now
  milliseconds. The `exit` really does stop the script. A file in WAL mode left by a crashed
  QGIS is refused even when it is blank. That fails toward refusal, and moving the file aside
  gets past it.
- **The `*.building.*` outputs and the final `mv`/`mv`/`cp`/`mv` (:174-177).** A failure partway
  through can leave a new GeoPackage beside an old `flags.csv`. It can also leave a missing or
  partial `review/sample_design.csv`. Every such state fails toward refusal:
  - `review_score.sh` refuses an md5 mismatch.
  - The next `review_build.sh` refuses at the `cmp`, or, where the design file is absent,
    rebuilds over an unfilled GeoPackage.

  Same-directory `mv` failures are not realistic in any case. No finding.
- **`DROP TABLE IF EXISTS fwapg.pcic_qa_gauges` at pcic_crosswalk.sh:17.** It runs before any
  step that can fail. On a job that fails early, before `pcic_outlets` exists, rerunning
  `qa_gauges.sh` rebuilds the gauges table from the still-present previous build, which is
  consistent. It cannot block a legitimate run. Its reach stops at the job: see the
  `pcic_qa_gauges` row above.

## Findings

- **[severity: bug]** review_build.sh:40-47, and the claim in the comment at :32-34. The
  cross-build invariant passes for a crosswalk from a different build whenever the two builds
  share candidates. As a result, the `following` and `flagged` strata, and `flags.csv`, silently
  describe a different placement from the one being reviewed.

  The comment says the check holds "only when they are one build". It actually tests only that
  every ranked placement is *some* candidate of that rank on that blue line, and that the outlet
  counts are equal. Candidates come from crosswalk02, which depends on the PCIC outlets and the
  FWA. Placement comes from crosswalk04-06. So a crosswalk placed by different selection or
  demotion logic, such as a published build from another commit loaded by `load.sh` or
  `load/pcic_fwa_crosswalk.sql`, passes over this database's local `pcic_qa_following`,
  `_drainage`, `_flow` and `_gauges`.

  Reproduced against a TEMP copy of the crosswalk:
  1. Moved 500 placed rank-1 outlets onto their rank-2 candidate on another blue line.
  2. Demoted 200 more.
  3. Ran the invariant: `mismatch = 0`, so it passes.

  In the same copy, `pcic_qa_following.blue_line_key` disagrees with the crosswalk for all 500
  moved outlets. The 200 demoted outlets enter the `unplaced` stratum while keeping `following`
  and `flagged` membership, and their drainage flags, computed for a placement that no longer
  exists.

  A tighter tie is already exact in today's data:
  - `pcic_qa_drainage` has one row per placed subid, and carries `blue_line_key` and
    `candidate_rank`. Against the crosswalk: 37,667 = 37,667, with 0 differences in
    `blue_line_key` and 0 in `candidate_rank`.
  - `pcic_qa_following` covers every placed river outlet (37,293 = 37,293) on the same
    `blue_line_key` (0 differences).
  - The subid set of `pcic_qa_flow` equals the placed set (0 differences).

  Adding to `mismatch` the count of placed rows whose drainage row is missing or differs in
  `(blue_line_key, candidate_rank)`, plus drainage rows with no placed row, returns 0 today and
  700 on the simulated mix. A `following`/`flow` subid-set check covers those two tables the
  same way.

  One residual remains: `load.sh` also replaces the discharge table, so `pcic_qa_gauges.q_fwa`
  and `pcic_qa_flow.q_fwa` can differ under identical placements. Neither the current check nor
  the proposed one can see that. Either drop `pcic_qa_gauges` in `load/pcic_fwa_crosswalk.sql`'s
  sibling discharge load, or state it as accepted.

- **[severity: fragile]** review_build.sh:73, :92 and :175. On the path the script prescribes
  for a new draw, `flags.csv` from the review in hand is overwritten, and it carries no
  `sample_id`. The path is:
  1. The filled `review.gpkg` is refused, and the script says to move it aside.
  2. The rerun refuses the `cmp`, and the script says to move the design aside.
  3. The rerun builds.

  Step 3's `mv` at :175 replaces the old review's `data/review/flags.csv` with the new draw's.
  Neither message mentions it, and the old values are lost: crosswalk flag, rank, drainage and
  following flags, flow ratio and gauges as of that build. By then the job has been rerun, so
  they cannot be regenerated. `flags.csv` has no `sample_id`, and `review_id` is reassigned per
  draw, so joining the moved-aside review to the current `flags.csv` by `review_id` gives each
  outlet another outlet's flags without an error.

  Fix: put the `sample_id` in `flags.csv`, as a column or in the file name, and name `flags.csv`
  in the move-aside messages. Alternatively, refuse at :175 when an existing `flags.csv` does not
  belong to the same design.
