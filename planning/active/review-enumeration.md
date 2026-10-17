# Code-check termination: enumeration (#25, 2026-10-17)

The code-check loop is ended by enumeration, not by a quiet round. Round 2 found a defect inside round 1's
fix (the stale-row deletes enumerated runs only from pcic.runs), and round 3 found one inside round 2's
(the gauges-run check did not cover the run's flow being present).

**Mechanism** (round 3): three facts are each kept in several copies with separate writers, and each guard
read one copy as if it were the fact:
- which runs exist;
- what a run's rows were built on;
- which outlets have no series.

**Candidate set**, measured with `git grep` over the branch outside planning/ and *.md. Every file that
names `pcic.runs|fwa_crosswalk|segment_weights|day_bins|subbasin_daily|discharge_*`, `missing.txt|no_series`,
`pcic_qa_build`, or a hard-coded run or period:

| File | Verdict |
|---|---|
| pcic_crosswalk.sh | run identity from validated variables. The stamp now carries the run's monthly fingerprint (round 3). The no-series count reads `fwapg.pcic_outlet_daily`, the copy placement reads (round 3) |
| sql/pcic_export.sql | crosswalk, weights and orphan guards (rounds 1, 2) |
| load/pcic.sql | incoming fingerprints, local runs, orphans, stale published rows (rounds 1, 2) |
| load/pcic_run.sql | the file's run is in pcic.runs and matches its fingerprint, on pcic.fwa_crosswalk |
| load/pcic_schema.sql | DDL only |
| load.sh | the hard-coded run list is checked against pcic.runs before loading (round 3) |
| qa_gauges.sh, sql/qa_gauges.sql | the run's monthly flow is checked present, as pcic.runs lists it (round 3). Gauges record their run (round 2) |
| review_build.sh | stamp md5 = crosswalk; gauges' run = stamp's run (round 2); pcic.runs still holds the stamp's monthly fingerprint (round 3) |
| sql/review_sample.sql | reads pcic.fwa_crosswalk only after review_build.sh's three checks |
| qa_gauge.sh | single-gauge display; an absent run shows as NULL flow in its output. Accepted |
| load/pcic_fwa_crosswalk.sql | frozen first build, a comment match only |

Accepted residuals:
- `pcic.day_bins` has no fingerprint. It is a constant of 01_days.sql, and a change to the week formula
  must rebuild every weekly run.
- The weights fingerprint (round(share, 9)) could differ in a last digit with float summation order. This
  is unmeasured; a refusal is the safe failure.

Nothing in the set sits above its source of truth, so the loop ends here: 3 rounds, 14 findings, all fixed.
