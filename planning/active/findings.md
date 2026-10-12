# Findings — PCIC crosswalk: visual review of a sample of placed outlets in QGIS (#8)

## Issue context

**If we do it:** a measured error rate for outlet placement (with a confidence interval), from someone looking at PCIC's network and the FWA side by side, plus a reviewed list of what the automatic checks miss. **If we never do:** placement quality is known only through automated tests and the gauge comparison.

## Problem
Every placement bug found in #5 (six code-check rounds, PR #6) sat at confluences, braids, side channels or the BC boundary, and each was found by measurement after the fact. No one has looked at placed outlets on a map. Snap distance alone does not show whether the chosen FWA stream is the one PCIC's segment follows.

The automatic checks catch gross errors only: the gauge check (`qa_gauges.sh`, FWA flow within 10% of PCIC's at 494 of 538 gauges) and the drainage check (#7, 342 main-stem outlets flagged). A wrong stream of similar size, within about 5 times the area, passes both. Only a person looking at the map can find those.

## What this gates
Sending the crosswalk upstream (#20), not publishing it (#9). Publishing is fork-only and cheap to redo: a fix the review leads to is a rerun and a re-upload. What goes upstream should carry a stated error rate.

## Proposed solution
- [ ] **Size the sample on the current build first.** Count each stratum, then cap it (30-50 per stratum is enough for a usable 95% interval) so the review is days, not weeks. Strata: random placed outlets; placed with `candidate_rank > 1`; `broken_chain`; `demoted`; within 200 m of an FWA confluence; and the outlier lists in the comments below (the 34 gauge disagreements, the 85 outlets over 10x PCIC's flow, the 342 drainage flags). The flagged lists are sampled, not reviewed in full; the random stratum is what the error rate for the whole network comes from.
- [ ] **`review_build.sh`** writes `data/review/review.gpkg` from the job's data cache and outputs:
  - `review`: one point per sampled outlet, keyed by a shuffled `review_id` that is also the working order, with the review fields empty: `verdict` (right / wrong stream / wrong position / should not be placed), `confidence` (high / low) and a free-text `note`. It carries no stratum, flag or `subid`, so the reviewer cannot tell why a point was drawn.
  - Context: PCIC river segments and lakes, outlet and probe points, every FWA candidate per outlet, the chosen position, and the FWA streams around them.
  - `flags`: the automatic flags and the stratum per `review_id`, as a separate layer for after the review, never shown while reviewing.
  - The sample design (`review_id` to `subid` and stratum) is written beside the GeoPackage, not inside it.
- [ ] The review project is built outside this repo from that GeoPackage. The filled-in `review` layer comes back as a GeoPackage of the same schema.
- [ ] **`review_score.sh`** reads the filled-in GeoPackage, joins the sample design, and reports the error rate per stratum with a 95% interval. It refuses a GeoPackage drawn from another sample.
- [ ] Each new failure class becomes a QA test in `sql/qa.sql`, and its fix a rerun.

## Order
After #14: its rerun moves 6 outlets across a confluence, so the review should look at that build. Then #20.

Not yet offered upstream.


## Plan-gate exploration (2026-10-11)

- Strata on the post-#14 build (fwapg DB, 2026-10-11): placed 37,667; `candidate_rank > 1` 608; `broken_chain` 985; `demoted` 43; `no_candidate` 9,993; `no_series` 28. `pcic_qa_gauges`: 33 of 604 rows outside 0.9-1.1 with no matching PCIC branch. `pcic_qa_drainage`: 218 `small`, 126 `big`. >10x PCIC flow: 85 (run14b.log, qa_report.sql).
- Confluence as written (placed outlet within 200 m along its blue line of any junction, from `blk_paths.path_blks[1]`/`path_measures[1]`): 27,869 of 37,667 (74%), since PCIC outlets sit at confluences by construction. By tributary stream order minus the main stem's (max order on the tributary vs the placed segment's): gap <= 0: 4,073; gap 1: 7,596; gap 2: 6,597. User chose gap <= 0.
- User: "Days of review? Don't have it.. what is the minimum sample that is meaningful?" Sizing: 0 errors in n gives a 95% upper bound of about 3/n (30: 10%, 60: 5%, 100: 3%); 10 draws from a stratum find a class affecting 20% of it with probability 0.89. Chose 60 random + 12 per flagged stratum (~120 outlets), plus an automatic line-following check over every placement.
- The job drops `pcic_outlets`, `pcic_candidates`, `pcic_rivers`, `pcic_outlet_monthly`, `pcic_subbasins_monthly` at step 5; `qa_gauges.sh` uses and drops `fwapg.pcic_qa_rivers`.

## Errors Encountered

| Error | Resolution |
|-------|------------|
