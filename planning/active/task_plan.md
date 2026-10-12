# Task: PCIC crosswalk: visual review of a sample of placed outlets in QGIS (#8)

## Problem
Every placement bug found in #5 (six code-check rounds, PR #6) sat at confluences, braids, side channels or the BC boundary, and each was found by measurement after the fact. No one has looked at placed outlets on a map. Snap distance alone does not show whether the chosen FWA stream is the one PCIC's segment follows.

The automatic checks catch gross errors only: the gauge check (`qa_gauges.sh`, FWA flow within 10% of PCIC's at 494 of 538 gauges) and the drainage check (#7, 342 main-stem outlets flagged). A wrong stream of similar size, within about 5 times the area, passes both. Only a person looking at the map can find those.

## Context
Every placement bug in #5 was found by measurement after the fact. The gauge check and the drainage check (#7) catch gross errors only and miss a wrong stream of similar size. #8 wants a stated error rate before the crosswalk goes upstream (#20). #14, which the issue says must come first, is merged.

Decided at the plan gate:
- **Automate the similar-size case.** A new check asks whether PCIC's river segment *follows* the FWA blue line the outlet was placed on, compared with the line of every other candidate. It runs over every placement.
- **Shrink the human review.** About 120 outlets, a one-click verdict each, about an hour. It gives the network's error rate with a 95% interval (60 random outlets) and calibrates the new check (its flags are a stratum).
- **Confluence stratum:** within 200 m along the blue line of a junction whose tributary's stream order is at least the main stem's (4,073 outlets; the issue's definition covered 27,869, 74%).
- **Verdicts:** right / wrong stream / wrong position / should not be placed / should be placed. 'right' on an unplaced outlet means it was correctly left unplaced.
- **Sample design** (review_id to subid and strata): beside the GeoPackage under `data/review/`, and committed to `extras/pcic_crosswalk/review/`.

This PR delivers the check, the tooling and the drawn sample. The review (about an hour), its score and the QA tests it leads to land after the merge, so #8 stays open.

## What exploration found
- The job drops `pcic_outlets` (outlet and probe points), `pcic_candidates`, `pcic_rivers` and the monthly tables in step 5, so the ">10x PCIC flow" list (85) and the candidates cannot be rebuilt from the published outputs. Kept today: `fwapg.pcic_qa_drainage`, `fwapg.pcic_qa_gauges`, the crosswalk, `fwapg.blk_paths`.
- `qa_gauges.sh` writes and then drops `fwapg.pcic_qa_rivers`, so that name is taken.
- `blk_paths.path_blks[1]` / `path_measures[1]` are the parent line and the junction measure on it, so the confluence stratum is one join.
- Current build: placed 37,667; `candidate_rank > 1` 608; `broken_chain` 985; `demoted` 43; gauge disagreements 33; >10x 85; drainage `small` 218, `big` 126.

## Phase 1: Line-following check (`sql/qa_following.sql`)
- [x] For each placed river outlet: the PCIC segment's first ≤1 km up from its outlet, and for each of its candidates the share of that length within a buffer of the candidate's blue line. Flag `follows_other` where another candidate's line follows clearly better, and `follows_none` where no candidate's line follows. The buffer and margins are set from the measured distribution, not guessed.
- [x] Measure: the distribution, the flag counts, and the overlap with the drainage, gauge and >10x lists.
- [x] Seeded errors, as #7 did: move N placed outlets onto another candidate of similar area and count how many are flagged; put the Nicola main stem back on Clapperton Creek.
- [x] Wire it into the job's QA step beside `qa_drainage.sql`: keep `fwapg.pcic_qa_following`, write `data/qa_following.csv`, and add a ceiling test to `sql/qa.sql` set from the measured count.

## Phase 2: Keep the job's review inputs, rerun
- [x] Step 5: rename `pcic_outlets` and `pcic_candidates` to `pcic_qa_outlets` and `pcic_qa_candidates` instead of dropping them, and write `fwapg.pcic_qa_flow` (subid, mean annual q_pcic, q_fwa) from the `annual` CTE `qa.sql` uses.
- [x] Rerun the job. Confirm it reproduces the published build (md5 of both `.csv.gz` before and after; stop and ask if they differ) and that `pcic_qa_flow` gives 85 over 10x.

## Phase 3: Tests first for scoring (`review_test.sh`)
- [x] Fixture GeoPackages from a committed fixture design. Assert:
  - known verdicts give the hand-computed per-stratum rates and Wilson intervals
  - a GeoPackage carrying another `sample_id` is refused
  - a GeoPackage whose review_id set differs from the design is refused
  - an unknown verdict is refused
  - a partly reviewed GeoPackage reports n reviewed of n drawn and does not count the blanks as errors
- [x] Restore each guard's bug and watch the matching assertion go red (mutation table in findings.md).

## Phase 4: `review_build.sh`
- [x] `sql/review_sample.sql` draws deterministically (`md5(subid || stratum || seed)`, not `random()`): 60 random placed outlets, plus 12 each from `qa_following` flags, `candidate_rank > 1`, unplaced with a candidate (`broken_chain`, `demoted`), comparable-size confluences, and the existing flags (drainage `small`/`big`, >10x, gauge disagreements). An outlet drawn by several strata appears once and counts toward each. `review_id` comes from a second shuffled md5 order, which is also the working order.
- [x] Writes `data/review/review.gpkg`:
  - `review`: point at the PCIC outlet; `review_id`, `verdict` (empty), `confidence` (pre-filled `high`), `note` (empty). No subid, stratum or flag.
  - context keyed by `review_id`: the outlet's PCIC segment and the PCIC rivers and lakes around it (from `data/rivers.geojson` and `lakes.geojson`, clipped to a buffer around the sample), outlet and probe points, every FWA candidate (rank, blue line, name, distance), the placed position, and FWA streams in the buffer (blue line, name, order, edge type). Nothing that reveals a flag.
  - `flags`: review_id, strata, the crosswalk flag and the automatic flags, for after the review.
  - `sample`: one row holding `sample_id`, the md5 of the design file.
- [x] Writes `data/review/sample_design.csv` and copies it to `review/sample_design.csv`.
- [x] Self-checks before exit: the `review` fields are exactly the four review fields; per-stratum counts are min(cap, population); the review_id count matches the design.

## Phase 5: `review_score.sh`
- [x] Reads the filled `review` layer through GDAL (ogr2ogr to CSV, which also reads a GeoPackage QGIS left in WAL mode) and the design into psql temp tables, then runs `sql/review_score.sql`. It refuses on a `sample_id` or review_id-set mismatch, or an unknown verdict. It reports per stratum: drawn, reviewed, errors (anything not 'right'), rate, 95% Wilson interval, a breakdown by verdict, and low-confidence counts. It also reports the network rate (random stratum), the following check's precision (its stratum), and errors in the random stratum that no automatic check flagged.
- [x] `review_test.sh` passes.

## Phase 6: Build the sample, document
- [x] Run `review_build.sh` on the current build; commit `review/sample_design.csv`.
- [x] README: the line-following check (with its measurements), the kept `pcic_qa_*` tables, and a "Visual review" section covering strata and populations, blinding, verdicts and scoring, and noting that the QGIS project is built outside this repo.
- [ ] Edit the #8 body: the line-following check, the smaller sample, the confluence definition, the fifth verdict, the design file's home, and what is left after the merge.

## Validation
- [x] `review_test.sh` passes; `review_build.sh` self-checks pass on the real build; `sql/qa.sql` passes on the rerun
- [x] The job rerun reproduces the published outputs (md5)
- [ ] `/code-check` clean
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive`, then `/gh-pr-push` (base `newgraph`, `-R NewGraphEnvironment/fwapg`)

## Files
- `extras/pcic_crosswalk/pcic_crosswalk.sh` (step 5), `sql/qa.sql`, `README.md`
- new: `sql/qa_following.sql`, `review_build.sh`, `review_score.sh`, `review_test.sh`, `sql/review_sample.sql`, `sql/review_score.sql`, `review/sample_design.csv`

Branch: `8-pcic-crosswalk-visual-review-of-a-sample` off `newgraph`.
