## Outcome

Every segment of the main-flow tree now carries `upstream_area_ha`, the area draining through its downstream end along the tree, built by `extras/mainflow_tree/sql/mainflow_tree_area.sql` inside `mainflow_tree.sh` (about 5.5 min province-wide) and stored as a column on the tree table (#4). Each fundamental watershed polygon is given to one tree segment by the lookup's own rule (`FWA_Upstream`) and summed down the tree's nodes, so area is additive at every confluence and SSNbler's `afv_edges(infl_col = "upstream_area_ha")` runs with no overrides. What was learned: watershed codes say where a polygon could be, not where it is. Three rules written from codes alone (a polygon moving up its line through reaches with no polygon, a polygon going to the segments in its code range, a polygon going to a side channel that carries its codes) each put polygons on segments they do not touch, the worst a 767,000 ha cross-border polygon on the wrong river; a polygon now leaves the place its codes give only for a segment whose midpoint is inside it. The durable account is `research/fwa_mainflow_tree.md`, "Upstream area on the tree"; the rules, results and caveats are in `extras/mainflow_tree/README.md`.

## Measurement

On the provincial tree (4,510,368 segments, 3,245,453 polygons), final build, 2026-11-20 (`findings.md` has every figure with the query that produced it; `scripts/10_final_figures.sql` re-derives them).

**The problem, re-measured.** The lookup gives the four Skeena test side channels 4.26 to 5.11 million ha (the Skeena's); the tributaries entering them have 51,420, 228,943 and 302,611 ha. It matches 8,111 tree segments to a polygon of another stream's code, 71,402 to a polygon on their own stream at another local code, and has no row for 2,941. `FWA_WatershedAtMeasure()` returns no upstream area at a point on a segment with no local watershed code, because `FWA_Upstream` is NULL for a NULL local code (158,188 network segments not under `999`); a different path from #49, filed as #52.

**The result.** Every tree segment has a positive area; the areas at the 27,097 outlets sum to the 110,143,331 ha assigned; two builds give the same area to the bit. Polygons: 3,181,977 by their own code pair (15,867 of them moved up their line to a segment that lies in them), 12 by code range, 1,820 on side channels, 8,336 and 20 by the fallback rules; 53,288 belong to no segment (838,859 ha with no stream of their code in the tree, 3,623 under `999`, 351 below their stream's lowest main-flow segment). 1,898 segments with no polygon at or above them carry a length share of the polygon they lie in (181,075 ha, an estimate). The test side channels read 53,007 ha (tributary 51,420), 228,962 to 229,063 (228,943) and 302,611 to 302,813 (302,611). Area crosses 97 gaps (90 dead ends, 7 cut-offs); the other 383 dead ends and 1 cut-off are where the network ends (179,631 ha above them).

**Against the lookup**, classed by routing, not by the areas: of 4,362,376 comparable main-flow segments, 4,288,277 have nothing upstream routed differently and all but 293 of those agree (154 lookup rows that are not what the lookup's own definition gives, 138 segments with a local code more than one level deep, 1 not explained); of the 74,099 with something routed differently, 73,808 differ. Where a side channel flows into main flow (16,745 places) it takes a median 0.5% of the confluence with the tree's area and 50% with the lookup's.

**SSNbler** (the fork at 37ca338): four subsets clean, with SSNbler's values equal to plain arithmetic on every edge: a 3,190-line tributary basin, KLUM (24,732 lines, 8 min, 28.0 GB), the Bulkley (52,293 lines, parallel path, 21 min, 2.8 GB) and LTRE (8,484 lines, three outlets, two dead ends). With the lookup's area on KLUM's network the side channels take 0.5 of their confluence; with the tree's, 0.048 and 0.066. The whole Skeena was not run (the owner's decision): `afv_edges` is quadratic, hours at 262,000 edges.

**Cost.** The whole job: 46 min 34 s, of which about 35 min is the unchanged paths, tree and topology QA; the area build 5.5 min; the comparison 4.5 min.

**Wrong turns, kept** (each is in `findings.md` with its numbers):

- The plan told the owner area would cross 473 + 8 gaps. Measured, 97 can be crossed; the count was mine and unmeasured.
- A proxy for segments with no area (129) was off by two orders: 18,489 in the first prototype.
- A connector with no local code ended a run of reaches, so segments above it missed their polygon; found by tracing one unexplained 147 ha difference.
- "Local codes out of order" as a class for a whole stream took the Fraser, Skeena, Stikine and Nechako main stems out of the comparison; per segment it is 492.
- I recommended the code-range rule to the owner saying areas would change on 459 segments and nowhere downstream, on one example. Review round 3 found it had moved three cross-border polygons (63,000 to 767,000 ha) to the wrong lines. Geometry then showed the same assumption in two more rules: 6,368 of 23,897 polygons moved up their line, and 5,470 of 8,431 given to a side channel, sat on a segment that did not touch them.
- Counting routing markers instead of comparing sets let two differences cancel: 17 "unexplained" segments were mostly that, and 323 after a rule change; with sets, 1.
- The SSNbler check's literal for one test side channel was its mouth, which flows into another side channel (share 1); the place its water meets the Skeena is another segment (share 0.0104).
- A test written with a subquery per row did not finish in 10 minutes; as a join the whole test file takes 42 s.

**Review.** The Plan review, then five `/code-check` rounds over the branch (`review-4.md`, `review-round1.md` to `review-round5.md`, `review-verdict.md`). Rounds 3, 4 and 5 each found a defect inside the previous round's fix, all of one mechanism, so it ended on an enumeration: all 17,699 polygons away from their code position are on a segment that lies in them (round 4 re-derived every placement independently; it is now a test), and no polygon on a side channel holds its own stream's main flow. 27 tests; `scripts/08_restore_the_bug.py` restores 18 defects in rolled-back transactions and each test fires.

## Evidence

- `scripts/` in this directory: the measurement SQL (`01_` to `07_`, `10_`, `11_`), the restore-the-bug cases (`08_`) and the SSNbler lookup control (`09_`).
- `findings.md`: the record, phase by phase and round by round.
- Local and gitignored, on the machine that ran it: `extras/mainflow_tree/data/ssnbler/runs.log` and `*_area.log` (the SSNbler runs), `extras/mainflow_tree/data/qa_area.csv` (every tree segment that differs from the lookup, with its class).

## Owed

- Run the SSNbler area step on LSKE, which holds the place 360216952's water meets the Skeena, on a machine with more memory (about 29,000 lines on the serial path)

Follow-ups filed: #52 (`FWA_WatershedAtMeasure()` and segments with no local code), #53 (side channels and floodplain: which channel the land between them drains to). #33's body says what the tree's area no longer needs from the lookup.

Closed by: PR #54 (branch `4-upstream-area-on-the-main-flow-tree-so-s` into `newgraph`), merged 2026-11-20 at 2e2037d; #4 closed by hand the same day.
