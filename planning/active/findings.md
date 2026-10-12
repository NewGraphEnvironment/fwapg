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

## Plan review (Plan agent, 2026-10-12) and what was done with it

- md5 of `.csv.gz` can never match: gzip stores name and mtime, and both exports are `\copy <table>` with no ORDER BY (the monthly table is filled by `xargs -P 4`). Compare `gzip -dc | LC_ALL=C sort | md5` instead; copy the published files aside before the rerun.
- Phase 1 needs staging the job drops: rebuilt by hand for development (ogr2ogr rivers/lakes, `00_outlets.sql`, `02_candidates.sql`; 3.5 min). The rebuilt candidates reproduce 37,661 of 37,666 ranked placements exactly; the other 5 are outlets 06 moved 1 mm below a junction.
- `ALTER TABLE ... RENAME` fails when a previous run left the target: drop if exists first.
- Blinding: `flags` goes in a separate file, not a layer in `review.gpkg`; strip `subid`/`dowsubid` from PCIC rivers; candidates shown unranked (rank reveals the `candidate_rank > 1` stratum). Not addressed: a placed point off every candidate reveals one of the 6 outlets 06 moved.
- `confidence` left empty (pre-filled `high` makes an untouched record look answered); blank counts as high in scoring.
- Scoring also refuses duplicated review_ids.
- "Counts toward each" means each stratum that drew it, not membership, or flagged draws leak into the random stratum.
- Confluence stratum also includes the placed line's own mouth (a main-stem outlet put on a tributary near its mouth).
- md5 draw: separator between fields, `COLLATE "C"`, seed fixed and recorded.
- 12 per stratum gives a Wilson interval of about +/-25 points: that is a rough precision for the following check, not a calibration. Stated as such.
- The network rate covers placed outlets only.

## Line-following check (Phase 1, 2026-10-12)

Probe (`share` of the PCIC segment 100-1000 m from its outlet within B m of each candidate's line, grouped by watershed_key):

| | B = 50 m | B = 100 m |
|---|---|---|
| follows_other (other > placed + 0.5) | 248 | 246 |
| other > placed + 0.2 to 0.5 | 21 | 16 |
| follows_none (both < 0.2) | 186 | 132 |
| placed share, 5th percentile | 0.91 | 1.0 |

- 37,293 placed river outlets (374 lake outlets not checked), 761 with under 100 m to measure. Runtime 21 s.
- Other-minus-placed histogram (0.2 bins from -1): 34,571 / 776 / 406 / 272 / 107 / 131 / 18 / 12 / 51 / 160 / 28. Bimodal; 0.5 sits in the gap.
- Overlap: of 248 follows_other, 69 drainage-flagged, 40 rank > 1, 1 gauge disagreement; of 186 follows_none, 65 drainage-flagged.
- Seeded: each passing outlet moved onto another river's candidate: 12,792 of 12,848 flagged with area within 0.2-5x (99.6%), 32,607 of 32,765 otherwise (99.5%). Conditional on the right line being a candidate that follows PCIC.
- Nicola 3008978: share 1.0 on the Nicola, 0 on Clapperton Creek.
- 217 placed outlets have `direction_method = 'none'` (outlet end arbitrary); measured around the end that was placed.

Mutations of the qa.sql test (each in a rolled-back transaction), all red: a measured outlet with NULL placed share; 200 more follows_other; everything unmeasured.

## Job rerun (Phase 2, 2026-10-12)

- `data/run8.log`: 13:30:09-13:57:32 UTC (27.4 min), exit 0, all 17 `qa.sql` tests `t` including the new following ceiling.
- Outputs reproduce the published build: `gzip -dc | LC_ALL=C sort | md5sum` equal before and after (crosswalk `ddf99b6c...`, monthly `8079debe...`). The local copies matched S3's sizes before the rerun. Nothing to re-upload.
- `pcic_qa_flow`: 85 of 37,667 placed outlets over 10x PCIC's flow and over 1 m3/s, the same as `qa_report.sql`'s list.
- Following check in the job: 248 / 186 / 761 unmeasured, the same as the hand-built staging.

## Scorer (Phases 3 and 5, 2026-10-12)

- Design file is long format: `review_id, subid, stratum, drawn`. A row per stratum the outlet belongs to; only `drawn = t` rows enter a rate, so membership is known (for "random errors no check flagged") without leaking into the random rate.
- 13 tests in `review_test.sh`, all pass. Mutation table (each in a scratch copy), all red:

| mutation | caught by |
|---|---|
| M1 sample_id check off | another sample_id |
| M2 duplicate check off | a review_id duplicated |
| M3 id-set check off | a review_id missing; a review_id added |
| M4 'maybe' accepted as a verdict | an unknown verdict |
| M5 'sure' accepted as a confidence | an unknown confidence |
| M6 undrawn membership counted | membership without a draw does not count |
| M7 blank verdict counted as error | blank verdicts are unreviewed (scorer crashed: sqrt of a negative) |
| M8 unflagged filter off | random errors no automatic check flagged |

## Errors Encountered

| Error | Resolution |
|-------|------------|
| psql does not interpolate `:'var'` in `\copy` (`error: :: No such file or directory`) | load the temp tables with `-c "\copy ..."` in the same psql session as `-f` |
| `greatest(0, NULL)` is 0: an unreviewed stratum showed an interval of 0-1 | dropped the clamp; Wilson stays in [0, 1] by construction |
| Mutation probe read only `FAIL` lines, so M7 (scorer crashed, suite exit 3) read as "still green" | `score()` wrapper reports a crashing scorer as output, so checks fail instead of the run aborting |
