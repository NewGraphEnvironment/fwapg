# Plan review for #4 (Plan agent, spawned 2026-11-20T13:30Z, returned 13:46Z)

The reviewer's report as returned, paths made repo-relative. Verdicts on each finding are in
`findings.md` ("Plan review"); the plan changes they led to are in `task_plan.md`.

## Report

Plan lines refer to `planning/active/task_plan.md`.

## Verdict

Not ready to build as written. There is one blocker (decision 4's junction steps rest on a count the data does not support) and a set of gaps that would show up as failing or vacuous tests in Phases 2 to 5. Decision 6 does reproduce the lookup on plain main flow.

Not checked: the fork's `afv_edges` source (only SSNbler 1.1.2 is installed), the text of #33, #36 and #49, and anything that needs the area built.

## The three probes (read-only, each under 60 s)

**Probe 1. Skeena tree segments (`wscode <@ 400`), by how the lookup polygon's codes relate to the segment's.**

| source | lookup polygon | segments | top segment of its line |
|---|---|---|---|
| mainflow | same code pair | 256,453 | 89,173 |
| mainflow | same stream, other local code | 1,434 | 230 |
| mainflow | other stream | 104 | 13 |
| mainflow | no lookup row | 102 | 8 |
| reattached | same code pair | 2,476 | 772 |
| reattached | same stream, other local code | 1,124 | 471 |
| reattached | other stream | 32 | 0 |
| reattached | no lookup row | 34 | 4 |

(5 followed segments, all same pair.)

**Probe 2. The 481 dead ends and cut-offs in `fwapg.mainflow_tree_qa`: the highest segment of the `blk_parents` parent more than 1 mm below the junction measure.**

| | lands on a tree segment of the parent | no segment below the junction on the parent | no `blk_parents` row |
|---|---|---|---|
| dead ends (473) | 74 | 399 | 0 |
| cut-offs (8) | 4 | 3 | 1 |

All 7 cut-offs with a parent row sit at `downstream_route_measure > 0`.

**Probe 3. The three test tributaries (400.107640, 400.195432, 400.221484).** No segment of the Skeena main line (360887278) carries any of these codes as its local code. Their paths reach the Skeena at measures 63,193.8, 121,306.9 and 138,394.1.

## Blocker

**B1. Decision 4 carries area across about 90 dead ends, not 473 + 8, and the reused rule does not land on the tree.** Verified.
- Rests on: plan lines 81-84 and 140-142; `planning/archive/2026-10-issue-34-measure-downstream-queries/findings.md:114`; `planning/archive/2026-10-issue-34-measure-downstream-queries/scripts/sql/01_downstream_ids.sql:84-94`.
- Probe 2 shows 399 dead ends join their parent at the parent's lowest segment start. The #34 archive already measured the rest: 383 never reach a segment on any line of their path, and 90 take a junction step.
- The archive's rule 3 picks its target from `fwa_stream_networks_sp`, not the tree (lines 84-89), and only for a line's lowest segment (line 94). The cut-offs are mid-line, so nothing in the archive gives them a step onto the tree.
- The plan says "from `fwapg.blk_parents`"; with `blk_parents` alone, 402 of 480 steps have no landing segment.
- Smallest change:
  - Rewrite decision 4 and Phase 3 bullet 2: walk `fwapg.blk_paths` to the first line with a tree segment more than 1 mm below the junction.
  - Dead ends with none stay outlets and are counted (expect 383).
  - Add a Phase 1 checkbox that lists the 8 cut-offs one by one (does the line re-enter the tree below?) before their rule is written.
  - Tell the owner the corrected count, since 473 + 8 is what was approved.
  - Make the Phase 2 junction ceiling an equality with these counts.

## Gap

**G1. "The polygon is the segment's own" is defined by watershed code only, and the largest non-own class has no name.** Verified by probe 1; the disagreement itself is inferred.
- Rests on: plan lines 127-128 and 156-158; `planning/active/findings.md:34`; `load/fwa_streams_watersheds_lut.sql:38-51`.
- In the Skeena, 1,434 main-flow segments got a polygon of their own stream at another local code through the midpoint fallback, against 104 on another stream.
- Under decision 6 these segments get no local polygon, so they will differ from the lookup by a reach.
- Smallest change: define "own" as watershed code and local code both equal; add the class "same stream, other local code" to Phase 4; count it province-wide in Phase 1.

**G2. Main-river segments beside a reattached side channel will read less than the lookup, and neither the issue's criterion nor the class list covers them.** Inferred from probe 3 and `FWA_Upstream`.
- Rests on: `db/schema.sql:3215-3256`; `extras/blue_line_paths/sql/blue_line_paths.sql:15-20`; plan line 157.
- The lookup counts a tributary for every Skeena segment whose local code is below the tributary's code. The tree counts it only below the side channel's mouth.
- The Skeena segments between (from the mouth up to the next local code above the tributary's) have their own polygon and nothing reattached above them, yet differ by the tributary's area (51,420 ha beside 360216952).
- Smallest change: Phase 1 measures this stretch for the three tributaries; Phase 4 gets a class defined from `blk_paths` and codes (a main-flow line whose code is above the segment's local code reaches this line below the segment). Say whether "side channel above" in line 157 means this.

**G3. Zero-area segments are far more than the proxy of 129, and their rule shapes stored data.** Probe 1 is verified; "these get zero" is inferred.
- Rests on: plan lines 108-109 and 116.
- In the Skeena alone, 251 main-flow line-top segments (230 + 13 + 8) have no code-matched polygon. Nothing flows into a line's top, so most would accumulate zero.
- The proxy counts streams with no polygon under their watershed code; the miss is at the level of the code pair.
- Smallest change: recount in Phase 1 as "tree segments with no assigned polygon and nothing above", and bring the rule to the owner (see gate questions).

**G4. Decision 6 is underspecified in four places.** Verified by reading.
- Rests on: plan lines 87-92; `db/schema.sql:3235-3250`.
- "Uppermost" has no order across blue lines. That matters for the 8,449 polygons (407,571 ha) on reattached-only pairs, which can sit on several side channels.
- `followed` and `override` segments have no rank beside "main flow before reattached".
- Fallbacks 2 and 3 do not say strict or not. The lookup excludes a tributary at the same position, so both must be strictly below, and fallback 2 must name the uppermost segment of that pair.
- A polygon with no local code below it on its own stream falls through to the ancestor and leaves its own stream's mouth.
- Smallest change: one line each in decision 6.

**G5. Phase 1 does not break down the 8,449 reattached-only polygons.** Verified: lines 105-107 cover only the 53,225 and 2,985.
- These decide the "own polygons" of the four test side channels.
- Smallest change: add them to that checkbox, with a count of pairs on more than one line.

**G6. Local codes out of order have no class, and "uppermost" is sensitive to a stray segment.** Inferred.
- Rests on: `research/fwa_position_codes.md:11-14`.
- A pair that reappears far up a line (the Stikine's `600.119863`) would send its polygons in from there.
- Fallbacks 2 and 3 place polygons by the same code order the lookup uses, so the lookup comparison cannot test them.
- Smallest change: Phase 1 counts pairs in more than one run on a line and their area, then chooses between "uppermost" and "top of the lowest run".

**G7. The source of local area is not stated.** Verified.
- Rests on: `extras/lookups/sql/fwa_watersheds_upstream_area.sql:14`; `db/schema.sql:5427`.
- The lookup sums `ST_Area(geom) / 10000`; the polygon table also has an `area_ha` attribute.
- Smallest change: state `ST_Area(geom) / 10000` in Phase 3, and a relative float tolerance.

**G8. The SSNbler area step does not fit `ssnbler_check.sh`'s contract as planned.** Verified by reading.
- Rests on: `extras/mainflow_tree/ssnbler_check.sh:37-48, 99, 107-108, 174-186`; `extras/mainflow_tree/ssnbler_check.R:21, 91-93`.
- Arguments: `$outlets` is passed unquoted and R accepts 2 or 3 arguments. A sixth positional argument with no outlet count becomes R's third and is read as the outlet count. Expected outlets has no `-` placeholder.
- Exit status: an R error after the `node errors:` line exits 1, and the shell takes 1 with that line present as a topology failure. An NA area is exactly that case (`afv_edges` fails on `if (sum(ind) > 0)`).
- Exit status: R quits at line 92 on node errors before any area step, so the area result is absent.
- "Statuses keep their meanings" needs either a new status for area failures or a widened 1. That is a contract decision.
- "Fail on a warning": Rscript only prints warnings, and the zero warning fires only when an AFV is 0. Check the column directly.
- Export: it should select `upstream_area_ha` only when the step is on, or the script breaks on a tree built before this change.
- Sites: `afv_sites` needs a named list of sites carrying `rid` from `sites_to_lsn`. The plan names no site source or snap tolerance.
- Smallest change: one checkbox that fixes the switch (an environment variable leaves argument validation untouched), the status, a `tryCatch` around the step with its own result line, and the site recipe.

**G9. The level loop needs things the PCIC form does not have.** Inferred, with a documented mean.
- Rests on: plan lines 145-147; `extras/pcic_crosswalk/sql/pcic_crosswalk06_daily.sql:58-80`; `research/fwa_downstream_queries.md:25`.
- A random origin is about 1,160 steps from the sea, so maximum depth is in the thousands of levels.
- The PCIC loop filters by depth with no index on it, over 36,000 rows. At 4.5 million rows an unindexed level is a full scan per level, which is hours.
- With an index on depth, an unindexed target column and free space for in-place updates, it is about 4.5 million row updates and should be minutes. That is not measured.
- Smallest change: Phase 3 states the depth index and measures maximum depth and time on the Skeena before the province.

**G10. The fallback is sound only if its unit is a piece, not a blue line.** Inferred.
- Rests on: plan lines 146-147; `extras/mainflow_tree/sql/mainflow_tree.sql:17-19, 109-117, 162-164`.
- A line can be in the tree in several pieces (reattached below an entry, followed mid-line). Node steps also leave the route `blk_paths` gives.
- Smallest change: define the unit as a maximal run of tree segments joined by pointers on one line, build the piece tree from the segment pointer, and attach inflow at the target segment.

## Acceptance

**A1. "Additive at every node" reads its own pointer.** Verified (lines 117-118).
- It can only catch a broken loop.
- Smallest change: take node inflows from geometry as `extras/mainflow_tree/sql/qa_topology.sql:23-38` does, and junction inflows from the table. Add: junction sources equal the QA dead ends and cut-offs less the listed unresolved; NULL pointers equal the QA outlets.

**A2. "Non-decreasing along every pointer" can only pass once A1 does.** Verified (line 119).
- The issue asks for "along each line".
- Smallest change: test consecutive touching tree segments on one blue line, by measure.

**A3. Parts of the conservation test can only pass.** Verified (lines 120-121).
- "At most once" is a primary key. "Assigned plus unassigned equals total" is true by construction if the unassigned table is the complement.
- The outlet sum is a real test.
- Smallest change: keep the outlet sum, and test "no unassigned polygon without a class".

**A4. The must-agree domain exempts most of every large river, and difference classes have no ceilings.** Inferred.
- Rests on: lines 127-128 and 131.
- "Nothing reattached above" removes every segment below any of 19,745 side channels. Below a side channel's mouth the two should agree.
- Under decision 4 the lookup also counts a dead-end tributary by code, so "gap above" should mostly agree too.
- Without a ceiling per class, a regression is absorbed by a class.
- Smallest change: define classes by predicates on codes, paths and the lookup (not on the area tables), set a measured ceiling for each, and require agreement below reattached mouths if the Phase 1 prototype shows it.

**A5. The side-channel test is partly circular.** Verified (lines 124-126).
- "Polygons listed as their own" reads the assignment.
- Smallest change: cap the own-polygon total with the measured literal (18.3 ha for 360216952), and take the tributary's expected area from `sum(ST_Area)` of polygons under its code.

**A6. Phase 5's failure conditions cannot detect a wrong area.** Verified in the installed 1.1.2 source.
- AFV in (0, 1] and outlet AFV of 1 hold by construction for any positive areas; the lookup's side-channel areas would pass.
- Smallest change: assert the segment proportion of the four side-channel edges by `linear_feature_id` (about 0.01 for 360216952, not about 0.5), or run the lookup's area on KLUM as a control.

**A7. "Done when" lines with no test or pass line.** Verified.
- "Along each line, area never decreases" (see A2).
- "Minutes, not hours": line 150 records a time with no budget, and excludes the cost of the new tests.
- "No overrides" (see A6).

**A8. A test that returns no rows prints nothing and passes.** Verified.
- Rests on: `extras/mainflow_tree/mainflow_tree.sh:26-31`.
- Smallest change: a Phase 2 note that every test is an aggregate with no `GROUP BY`, or a count of expected lines.

## Ordering

- **O1.** The "zero unclassed" test needs `fwapg.mainflow_tree_area_qa` from Phase 4, but the restore-the-bug check is in Phase 3 (line 152). Move `qa_area.sql` into Phase 3 or the check after Phase 4.
- **O2.** No checkbox runs `qa_area.sql` from `mainflow_tree.sh` before `qa.sql` or exports `data/qa_area.csv`. Line 150 puts the area build after `mainflow_tree.sql`; put it after `qa_topology.sql` so junction sources can be checked against `fwapg.mainflow_tree_qa`.
- **O3.** "Tests first" cannot hold for the ceilings or classes, whose numbers come from Phases 1, 3 and 4. Phase 2 tests also error (missing relation) and abort the script; they do not print `f`.
- **O4.** Phase 7 runs the whole job, then `/code-check`, whose fixes can change the SQL after the recorded run and after Phase 5's SSNbler runs. Add: rerun the area and tests after the last SQL change, and compare a checksum of the column with the one SSNbler ran on.
- **O5.** Add a Phase 1 prototype on the Skeena (pointer, assignment, accumulation in temporary tables, differences by candidate class). It settles G1, G2, G6, G9 and A4 before tests are written.

## Assumption

- **`afv_edges` at Skeena scale is untested and quadratic.** Verified in 1.1.2; the fork is not installed. `get_segment_pi` does `which(edges$rid == rid)` and a row assignment into an sf object per edge; `afv_edges` calls `shortest_paths` and `%in%` over all rids per edge. Time KLUM, extrapolate by the square of the line count before the Skeena, and say what happens if it is hours.
- **Cycles.** #34's pointer, with 90 junction steps, was acyclic. The planned check (every segment reachable from an outlet) is sound for the new one. The plan does not say what happens when it fires; state it (drop the step, list it as an outlet).
- **No double counting.** Each segment has one pointer and each polygon one segment, so a junction step cannot double count. Verified by reading.

## Scope

- One pull request is reviewable only if Phase 5 stays a small script change. The Skeena run's time is unknown (see Assumption), so name the split now: Phases 1-4 and 6 as one, Phase 5 as a second if KLUM's timing extrapolates to hours.
- `fwapg.mainflow_tree_area` keeps `downstream_id` (line 149) while "Not in scope" (line 216) leaves a stored pointer to #36. Either document it as QA-only or drop the column after the build.

## Gate questions for the owner

1. Decision 4 with the real count: about 90 dead ends carried, 383 staying outlets, cut-offs case by case.
2. The rule for zero-area segments. Options: move the first polygon below up to the line's top (changes nothing downstream), a spatial fallback, or NULL against the issue's first criterion.
3. "Uppermost" or "top of the lowest run" for a pair that appears in two runs on a line.
4. The exit status for an area failure in `ssnbler_check.sh`.

## Holds up

- Decision 6 on plain main flow reproduces the lookup: `FWA_Upstream` depends on codes only and includes the polygon and every polygon of its pair (`db/schema.sql:3247-3250`). Several polygons on one pair agree, and a headwater reach's whole polygon goes to its top segment, as the lookup has it.
- A tributary mouth inside the river's polygon gets no local polygon and carries the tributary's total, as tests 6 and 7 want.
- The node pointer and its primary-key assertion, the cycle check, the storage choice, the `qa.sql` contract and the claim that no loader reads the export all match the code.

### Critical Files for Implementation
- planning/active/task_plan.md
- planning/archive/2026-10-issue-34-measure-downstream-queries/scripts/sql/01_downstream_ids.sql
- extras/mainflow_tree/sql/qa.sql
- extras/mainflow_tree/ssnbler_check.sh
- db/schema.sql
