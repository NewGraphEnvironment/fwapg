## Outcome

Replaced the issue's days-long visual review with two parts. The first is an automatic line-following check (`sql/qa_following.sql`) run over every placement in the job's QA step. It asks whether PCIC's segment follows the FWA line the outlet was placed on, compared with its other candidates' lines, and catches the similar-size wrong stream that the gauge and drainage checks miss. The second is a blinded review of 119 outlets with one-click verdicts (`review_build.sh`, `review_score.sh`, `review_test.sh`, committed design `extras/pcic_crosswalk/review/sample_design.csv`): 60 random outlets for the network's error rate, plus 12 from each of five strata. The job now keeps its review inputs (`pcic_qa_outlets`, `_candidates`, `_flow`) and stamps them with the crosswalk's md5. Four code-check rounds each found the same mechanism, a fixed name standing in for provenance and ownership: a rebuild deleting answers, a GeoPackage open in QGIS or with a stray `-wal`, a partial build at the live path, QA tables from another build. The loop ended by enumerating every table and path the review scripts touch (`findings.md`). The review itself, its score and the QA tests it leads to come after the merge, so #8 stays open.

## Measurement

- Line-following check, 2026-10 build: of 37,293 placed river outlets, 248 `follows_other`, 186 `follows_none` and 761 `unmeasured`. 179 of the 248 are in no other flag list. The share difference is bimodal, with a gap between +0.2 and +0.6, so the 0.5 margin sits in the gap rather than on a guess. A 100 m buffer instead of 50 m gives 246 and 132.
- Seeded errors (each passing outlet moved onto another river's candidate): 99.6% flagged where the other stream's area is within 5 times the placed one's (12,848 seeds), 99.5% otherwise (32,765). The Nicola main stem put back on Clapperton Creek is flagged.
- Strata, population (drawn): random 37,667 (60), confluence 7,001 (12), unplaced 1,028 (12), rank_gt1 608 (12), following 434 (12), flagged 380 (12); 119 distinct outlets. The confluence definition the issue first proposed (any junction within 200 m) took 74% of placements.
- Two full job reruns (27 min, then 59 min with gauges and review build) reproduced the published outputs exactly: sorted decompressed md5 `ddf99b6c…` (crosswalk) and `8079debe…` (monthly discharge). `qa_gauges.csv` was byte-identical and the draw unchanged.
- Wrong turn kept: round 3's cross-build invariant (each ranked placement on its candidate of that rank) passed a crosswalk placed by other logic over the same candidates: 500 moved and 200 demoted outlets gave `mismatch = 0`. Replaced by the md5 stamp.

## Evidence

`extras/pcic_crosswalk/data/run8*.log`, `data/qa_gauges_run8b.log`, `data/review_build_run8b.log` (local, untracked); review rounds in this directory (`review-round*.md`).

Closed by: PR (link in #8)
