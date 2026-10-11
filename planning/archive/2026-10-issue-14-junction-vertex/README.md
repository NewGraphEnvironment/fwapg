## Outcome

Fixed flow and placement at tributary junctions in `extras/pcic_crosswalk` (fwapg#14). One convention drove both defects: FWA measures run `[downstream, upstream)`, so a tributary's junction is the start of the main-stem segment above it, and its water passes only the segment below. The 07 passing test, and the step>0 rules in 06 (FWA parent) and 07 (segment ownership), are now strict at the junction, within 1 mm. An outlet on a vertex whose placed PCIC descendant joins there moves to the nearest usable segment below, landing 1 mm below the junction. Line mouths and stacked outlets stop the job rather than being handled. `fwapg.blk_on_or_upstream` is unchanged for placement (04/05).

What was learned:
- The plan's "6 outlets" understated the reach: 94 vertex outlets have a line joining at their measure.
- Code-check found a bug that predates this work: an outlet 1e-14 m above a junction made its tributary skip it, and a 2,130 ha tributary carried no flow in any month.
- The mechanism behind three review rounds was comparing measures built from different FWA fields. `upstream_route_measure` misses the next segment's start by up to 9.3 mm.

The durable findings are in `research/fwa_position_codes.md` ("Which side of a junction", "Measures that name the same point disagree, by field").

## Measurement

Final run (eae70af) against the #13 build:
- 15/15 QA passed: 10 existing tests and 5 new, each shown to fail on the #13 build.
- Crosswalk: 6 rows changed (5 by about 1 mm; 5014089 by 43.8 m past a segment with no fundamental watershed). `fwa_parent_subid` is identical everywhere.
- Segments: 4,695 changed flow, 3,892 of them junction-start segments. 1,052 that had no flow now carry some. 135 that carried only a tributary's misplaced step now carry none. 13 secondary-flow segments at two coastal mouths left the output.
- Junctions where the step lands on the segment above: 2,373 -> 678 of 18,942 (June, tributary > 1 m3/s); held under 1,000 by QA.
- Flow at river mouths: unchanged (21,366.4 m3/s annual mean).
- Gauges: unchanged at 494 of 538 within 10% of PCIC. FWA flow moved at 2 of 604 gauges (Columbia above Nagle Creek 551.1 -> 544.1 m3/s).
- Fingerprint: `fwa_stream_networks_discharge_monthly` 40,524,444 rows, 3,377,037 segments, `sum(round(q_m3s::numeric, 6))` = 178035348.248310 (#13: 40,524,600 / 3,377,050 / 178168114.938520).

Wrong turns, kept:
- The plan's move landed on the segment below's `upstream_route_measure`. Rounds 2 and 3 each found the landing could still sit within noise of a junction, and the stacked-outlet guard covered only the old position.
- A mutation probe that piped job SQL extracted with `awk` into psql created a stray staging table (dropped; see `findings.md`, Errors).

## Evidence

`extras/pcic_crosswalk/data/run14*.log` and `extras/pcic_crosswalk/data/qa_gauges_run14b.log` (gitignored, on the machine that ran the job); `review-1.md` and `review-round*.md` in this directory.

Closed by: the PR into `newgraph` for fwapg#14.
