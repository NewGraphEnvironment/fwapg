# Code-check round 4: #24 diversions (round-3 fixes, and round 3's table walked)

## Checklist read

- code-check-infra.md: in full.
- code-check-python.md: in full.
- code-check.md: "A proxy is not the property", "Verification that reads its own output" and "A guard's scope, escape hatches, and remedies" in full, tables included. I read the prose of the other 11 H3s under `## Mechanisms` and skipped their `|` rows. I judged the 23 H3s outside Mechanisms from the index.
- code-check-shell.md: 1 of 67 headings read ("psql does not interpolate `:'var'` inside a dollar-quoted string, and `\quit N` exits 0"). I did not read the other 66.
- code-check-r.md: 1 of 111 read ("Postgres row order is never fixed unless the query fixes it"). I did not read the other 110.
- code-check-spatial.md: 3 of 93 read ("FWA `upstream_route_measure` misses the next segment's start", "A Freshwater Atlas main stem's downstream end lies on the receiving river's centreline", "FWA main flow is not edge type 1000 alone"). I did not read the other 90.
- The six indexes: I read them as the repo `CLAUDE.md` carries them, which is the same index. The heading counts match the index files (37, 6, 111, 67, 93, 37).

Database: read-only SELECTs only (session `default_transaction_read_only = on`), on `whse_basemapping.*` and `fwapg.blk_paths`. One query hit its own 300 s timeout and returned nothing. I did not run the job, the tests, the mutation script, or any write. I edited no repo file except this one.

## Clean

I found no defect inside the round-3 fixes. Every row of round 3's table now holds generically, is loud with a correct message, or is Nechako-specific on purpose. The generic checks that table left out also hold or are loud (below).

Probes behind that verdict:

- **03's exit-vertex refusal (03:94-103).** It reads the same source as 06's step > 0 rule and qa.sql:113, `fwapg.blk_paths.path_measures`, so it is not one fact derived twice. Within 1 mm it is that rule's failure band. The one gap is a join at exactly +1 mm, which would need a 1 mm exit segment.
  - It runs after the usable-exit check, so `dv.downstream_route_measure` is never NULL when it runs. A NULL there would have let it pass silently.
  - A line that joins through a second line is covered too, because that second line's own mouth is at the exit.
  - Measured: it does not fire at the Nechako exit (701799415, measure 288852.35). No line joins within 50 m there.
  - Measured: it fires at 1 of 6,163 lake exits (edge type 1200, the lowest segment per line and lake) in LNRS, UNRS, LEUT and UEUT. That hit is the positive control: it shows the predicate can fire. It also shows that the refusal's extra breadth (below) costs about 0.02% of lake exits.
- **Area test (qa.sql:307-329), position-parent conjunct.** It now tests the definition. Both of round 3's mutations fail it for any diversion with more than 0.01 ha of upstream area:
  - the area comes off no sub-basin: the P side is off by T;
  - the area comes off the flow parent: the R side is off by T.
  - A double subtraction fails the R side as well.
- **06 guard 2's new message.** It names both arms and the two-route need. Its claim of a double add is true: with P = R, 07's FILTER (`c.fwa_parent_subid = s.subid = R`) and its CASE both add the diversion on R's own segment.
- **06 guard 3's new comment.** It is true. With y higher on R's segment, y owns that segment, and R owns none. The diverted flow still reaches the segments under R through R's `q_acc`. qa.sql:348 would then read n = 0.
- **README 114-116.** The new sentence ("a placed outlet on each route below the lake, and no other line joining at the exit vertex") is looser than the code.
  - Read literally, a single outlet shared by both routes satisfies it. That is the P = R case, which 06 refuses.
  - It leaves out guard 3 and 03's lake-outlet and usable-exit refusals.
  - It is not a defect. Every case it admits is refused loudly, and each refusal states the real condition. Worth tightening when the Phase 4 caveat is written, for example to "a placed outlet on the FWA's route below the exit that is not the PCIC ancestor".

## Round 3's table, walked against the current tree

| place (current lines) | verdict now | why |
|---|---|---|
| qa.sql:321, area test, P conjunct | **generic, holds** | Tests the definition. Fails both mutations round 3 named, for any diversion over 0.01 ha. A wrong `position_parent_subid` itself is out of its reach, by design: `kids` uses the same coalesce 06 uses. Guard 2 and the generic FWA walk that produces it cover that |
| qa.sql:320, area test, R conjunct | **generic, holds** | Unchanged since round 2 |
| 06:184-192 guard 2, and qa.sql:247 | **loud, correct message** | Refuses P = R and a NULL P. The message now names the two-route need and the double add in 07, and I checked that the double add is real. The placement-only listing is an accepted refusal |
| 06:193-211 guard 3 | **loud** (accepted over-strict) | The comment now states that it is stricter than flow needs and why. I verified the comment's claim (above) |
| 03:94-103 exit-vertex refusal (was "06:94-95 exemption, a stop that cannot be cleared") | **loud, up front** | Same source and band as 06's rule. 0 at the Nechako, 1 of 6,163 lake exits. Wider than the failure: it also refuses a joining line that carries no placed descendant of the diversion. Rare and loud, and the README states it as a requirement. Its message has no remedy because none exists |
| 03:63-92 refusals (lake outlet with a series; usable exit) | **generic, holds** | The exclusion terms still agree with 02:55-60. One NULL asymmetry: 03's `OR wscode_ltree <@ '999'` accepts a NULL code that 02's `NOT … <@` drops. Unreachable: 0 FWA segments have a NULL `wscode_ltree` (measured) |
| 03:14-15 "479; 4 have none" | **deliberate, historical** | Not re-derived: the `pcic`/`fwapg.pcic_*` tables are off limits during the build |
| comments at 04:170-172, 05:295-296, 06:18-20, 06:164-167, 07:35-39 | **generic, match the code** | Re-read against the current tree |
| README:110-116 | **generic** | See the README note above: looser than the code, but every case it admits is refused loudly |
| README:118-123, 139-141, 151-153, column rows 446/455/456 | **generic, match** | `candidate_rank` NULL for a diversion matches 04's `best` arm. The snap distance is measured to the probe, as in 02 |
| qa.sql:52-57 flow-drop note | **deliberate** | Unchanged |
| qa.sql:160-161 child-on-another-line exclusion | **generic, holds** | The diversion's edge is tested by qa.sql:348 |
| qa.sql:241-259, apart from 247 | **generic, holds** | An independent walk over `pcic_outlets` |
| qa.sql:273, 300, 334, 370 | **deliberate Nechako** | Ids, measures and thresholds hard-coded |
| qa.sql:348 "exactly one segment" | **generic, within guards 2 and 3** | On P's segments the FILTER drops the diversion (its `fwa_parent_subid` is R ≠ P). The CASE adds it only where `s.linear_feature_id` is the own segment of R, the only sub-basin with `d.fwa_parent_subid = s.subid` |
| qa_report.sql:9-19 snap stats exclude diversions | **generic** | Unchanged |
| qa_report.sql:21-27 note (1008709/1001496, 1002307) | **deliberate** | Its columns are generic |
| research/pcic_routed_flow_periods.md:30-31, load/pcic_schema.sql:49 | **generic** | pcic_schema.sql:76 ("directly above the sub-basin") is as round 3 left it, and not wrong enough to break a consumer |
| planning/active/logs/mutation_checks.sh, nechako_measure.sql | **deliberate** | One-off evidence |

## Generic checks the table did not list

| place | kind | verdict |
|---|---|---|
| 03:94-103 exit-vertex refusal | refusal (new in round 3's fixes) | loud: see row 5 above |
| 06:177-183 guard 1 (unplaced, or no placed PCIC ancestor) | refusal | **generic, holds.** Its LEFT JOIN makes a missing crosswalk row refuse too |
| 06:275-283 cycle check | refusal, now reachable through a diversion | **loud, generic message.** If a diversion's PCIC ancestor R is placed upstream of the exit on the FWA, the chain down from R passes the exit. 03 has refused a line that joins at the exit vertex, so the first placed outlet at or below the exit is the diversion, whose parent is R: a cycle. The message ("a cycle") is true but does not name the diversion. No other check sees this case: guard 2 sees P ≠ R, and qa.sql:161 excludes diversions |
| qa.sql:5-19 "outlet segments carry accumulated flow" | QA predicate | **generic backstop for 07's CASE.** R's own segment carries R's `q_acc` only while the diversion is in its `upstream_subids`. Drop the CASE and this fails, whatever the diversion's size |
| qa.sql:323-329, the area test's INNER JOINs to `pcic_subbasins` (t, r, p) under `count(*) > 0` | completeness by count | **holds by data.** With two diversions listed, a missing `pcic_subbasins` row would drop one silently. It cannot happen today: a placed outlet's segment has a lut row (02, 03 and 06's move require one), and the lut is unique per segment (4,538,224 rows, 4,538,224 distinct). Measured: 0 lut rows lack `fwa_watersheds_upstream_area`. `t` is now only a filter |
| pcic_crosswalk.sh:496-500 drop and rename to `pcic_qa_diversions` | harness | **generic.** No reader of `fwapg.pcic_diversions` runs after the rename. pcic_test.sh, days_build.sh and review_build.sh never read it |
| 04 `best` diversion arm; 05:308 never blames a diversion | behaviour | **generic.** A child that breaks against a diversion stays `broken_chain`, so the demotion loop still terminates |

## Nothing else found

Checked: no `:var` sits inside 03's or 06's `$$` bodies. Each new check either RAISEs (with `ON_ERROR_STOP=1`) or is a qa.sql row behind the `|t$` gate, where a NULL result also fails. 03's `ORDER BY downstream_route_measure LIMIT 1` is unique on a blue line. `string_agg` order matters only in a message.
