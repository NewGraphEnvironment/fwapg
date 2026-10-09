## Outcome
Added a drainage-size check at every placed PCIC outlet (`extras/pcic_crosswalk/sql/qa_drainage.sql`), run in the job's QA step with a ceiling test. PCIC publishes no sub-basin areas, so PCIC's drainage is measured two ways — upstream river length and mean flow, each per FWA upstream km² at the placed segment, normalised by watershed group — and an outlet is flagged only when both agree. Learned: river length alone is biased at headwaters (FWA area above PCIC's network tip), flow alone is noisy; together they are clean. Side channels cannot be checked, because the watershed lookup gives them their main river's area. The check is a review list for #8 and a regression guard, not a per-outlet verdict.

## Measurement
- 37,040 main-stem placements: 218 `small`, 126 `big` (4 judged by runoff alone: lake-only PCIC subtrees), 0 `unmeasured`; 627 side channels not checked.
- 82 of the 85 outlets carrying more than 10x PCIC's flow are `small`.
- Seeded errors: Nicola main stem on Clapperton Creek → `big`; 200/200 small outlets moved onto 10x area and 198/200 big ones onto 1/10 → flagged. Not caught: a wrong stream of similar size (< ~5x).
- Against WSC gauges: 4 of 493 agreeing gauges flagged, 0 of 28 disagreeing — the checks see different failures.
- Wrong turns kept: length-only proxy (1,621 below 0.2, 1,135 of them headwater artefacts); all placements including side channels (639 small, mostly side channels with the main river's area).
- Code-check: 3 rounds; findings and fixes in `review-round*.md`.

## Evidence
Local: `extras/pcic_crosswalk/data/qa_drainage.csv`, `data/drainage_flags.csv` (posted to #8).

Closed by: PR into `newgraph` (branch `7-pcic-crosswalk-drainage-check-at-every-p`)
