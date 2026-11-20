# Review round 2 (#4): the branch at 1aacbf1, and round 1's fixes

Reviewed 2026-11-20 (17:03Z to 17:30Z) against the provincial database holding the build from
1aacbf1. The tree's `upstream_area_ha` column gave the record's checksum (`92bd48cb…`) before and
after this round's probes: every change made to watch a test fail was inside a transaction that was
rolled back, and the 13 area tests print `t` on the database as left.

## Checklist read

- `code-check-infra.md`: in full.
- `code-check-python.md`: in full.
- `code-check.md`: the prose of all 14 headings under Mechanisms (table rows skipped); under "Rules
  that stand alone", "An ordered dispatch makes severity ordering load-bearing, and nothing enforces
  it" and "Test the cold/create path of idempotent code, not just the warm no-op". Not read: the other
  12 stand-alone rules, Security (6), Spreadsheets and PDFs (4): 22 headings.
- `code-check-r.md`: "Postgres row order is never fixed unless the query fixes it, so a pick, a float
  sum and a presence check can each depend on it"; "`tryCatch()` nests its handlers, so a `stop()` in
  one is caught by a later one". Not read: 124.
- `code-check-shell.md`: "psql does not interpolate `:'var'` inside a dollar-quoted string, and
  `\quit N` exits 0"; "`a && b || c` runs `c` when any step before the `||` fails". Not read: 70.
- `code-check-spatial.md`: "FWA `upstream_route_measure` misses the next segment's start"; "FWA main
  flow is not edge type 1000 alone"; "A Freshwater Atlas main stem's downstream end lies on the
  receiving river's centreline, not at the confluence"; "A GDAL failure partway through
  `sf::st_read()` returns the rows read so far, with only a warning"; "Ask the file about its field
  names, not R". Not read: 89.

## Findings

Three, none of them a wrong number in the build as it stands. Round 1's fixes hold on every probe
below.

- **[severity: fragile]** `extras/mainflow_tree/sql/qa.sql:134-353` (with
  `sql/mainflow_tree_area.sql:199-230` and `sql/qa_area.sql:159-165`) — no test fails when round 1's
  second finding is put back. Restored in a rolled-back transaction: the 56 `lower` polygons
  (158,932.4 ha) that the rule before round 1 gave to reattached segments were moved back onto them
  (the old rule emulated in SQL: the tree segment of any source at the greatest local code at or
  below the polygon's, main flow first within a pair; it reproduces round 1's count and area
  exactly), with `local_area_ha` and `upstream_area_ha` corrected down both chains in
  `fwapg.mainflow_tree_area` and on the tree (712 segments change). `lower | reattached | 56` then
  shows in the polygon table and all 13 area tests print `t`. The three tests that read the
  comparison tables saw the tables of the good build, since `qa_area.sql` was not re-run; with the
  marker now taken by where a polygon is (`s.source != 'mainflow'`), a re-run would class the
  segments below as `side polygon`, which no test limits. None of the 56 is on the four test side
  channels. So the claim "Only rule 2 gives a polygon to a side channel" (README, the header of
  `mainflow_tree_area.sql`) is held by the build's joins and by nothing else. It is one count: over
  `fwapg.mainflow_tree_area_polygons` joined to the tree, rows with `source != 'mainflow'` and
  `method != 'pair_side'` are 0 now and 56 with the defect (the pair table below is the same fact
  from the codes).
  - **Rule:** code-check.md "Restore the bug and prove the guard fires"

- **[severity: fragile]** `extras/mainflow_tree/sql/mainflow_tree_area.sql:185-193` (`has_pair`),
  with `extras/mainflow_tree/README.md:52-53` and `:67` — a polygon whose exact pair is on no
  main-flow segment never takes rule 1's run, even where main-flow segments sit in its own code
  range (above its local code, below the next local code that has a polygon). It falls to `lower`
  and is given to the top of the reach below, so the segments in its range do not carry it.
  Measured: 96 `lower` polygons have such segments, 459 main-flow segments (837 km) in all; 429 of
  the 459 are in the comparison as `lookup polygon at another local code`, a class the tests hold
  only by a ceiling. The part the lookup itself confirms (the segment's lookup polygon is that
  `lower` polygon) is small: 18 segments on 6 polygons, 5.9 km, the tree 9,581 ha short of the
  lookup over the 18. Example: polygon 9971874 (840 ha) and 1000001932 (240 ha), both at
  `…590311.667951`, are given to segment 201081888; the five segments of blue line 360884436 from
  measure 7,642 to 9,149 have local codes above that and below the next polygon code, the lookup
  matches all five to 9971874, and they read 277.0, 261.4, 219.8, 135.0 and 127.1 ha, the top one
  from a length share of 9971874 (the share rule meant for "streams with no polygon of their own"
  is what fills it; up to 80 of the 869 share segments are of this kind). The README's "A reach
  with no polygon of its own so takes the polygon below it on its stream, which it lies in" does
  not hold for these. Not from round 1: `has_pair` predates it. A likely home, offered tentatively:
  let a run with no exact-pair segment take the polygon when it is the only run of its group, or
  say in the README that rule 1 needs the exact pair and what happens otherwise.
  - **Rule:** none

- **[severity: fragile]** `research/fwa_mainflow_tree.md:48` — "a segment with no local watershed
  code (158,188 network segments, …)". The database has 328,961 network segments with no local
  code; 158,188 is the count of those whose watershed code is not under `999`, which is how the
  record states it (`findings.md`, "158,188 network segments have a watershed code (not under
  `999`) and no local code"). The sentence lost the condition; the number is right for the
  population the record names.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

## Asked, with no finding

**Do the fixes hold?**

- `area_reach` main flow only: nothing that was placed is now unplaced by it, bar the two
  `ancestor` polygons round 1 already reports (now `below the tree`). `lower` is 1,754 before and
  after; the 56 that were on reattached segments are on main-flow reaches of their own watershed
  code at a lower local code. Every placement against the segment's codes:

  | method | polygons | segment source | same watershed code | segment local code at or above the polygon's | below it | on an ancestor, below the branch |
  |---|---|---|---|---|---|---|
  | `pair` | 3,181,977 | mainflow | 3,181,977 | 3,181,977 (3,158,080 the exact pair) | 0 | 0 |
  | `pair_side` | 8,431 | reattached | 8,431 | 8,431 (all the exact pair) | 0 | 0 |
  | `lower` | 1,754 | mainflow | 1,754 | 0 | 1,754 | 0 |
  | `ancestor` | 20 | mainflow | 0 | 0 | 0 | 20 |

- The rules partition the polygons by where their exact pair is, with no overlap:

  | method | polygons | exact pair on a main-flow segment | exact pair on a side channel |
  |---|---|---|---|
  | `pair` | 3,181,977 | 3,181,977 | 20,338 |
  | `pair_side` | 8,431 | 0 | 8,431 |
  | `lower` | 1,754 | 0 | 0 |
  | `ancestor` | 20 | 0 | 0 |
  | unassigned | 53,271 | 0 | 0 |

  So `area_side_top`'s `NOT EXISTS` against `area_reach` is the right test for "on no main-flow
  segment": `area_reach` holds every pair on a main-flow segment with a local code, and every
  polygon pair it holds is also in `area_pair_top` (a segment with the polygon's exact pair has
  that pair as its group, so its run has `has_pair`). No tree segment is under `999` or has a NULL
  watershed code, so the missing `999` guard on the `sd` join has nothing to reach.
- `below the tree` against the rules' lateral: the same table (`area_reach`), the same
  normalisation of the local code, the same comparisons (`<=` on the stream, `<` the branch on each
  ancestor), so the two cannot disagree on a polygon. A NULL local code takes the watershed code in
  both (0 polygons have one; 1,457 have one not under their watershed code). It follows that an
  unplaced polygon outside `999` always gets `no stream` or `below the tree`: the `class IS NULL`
  clause can fire only if the two copies of the predicate drift apart, and the ceilings (3 and
  53,208) are what hold the data. The three `below the tree` polygons check out: SIML's two are on
  `300.432687.380566`, whose lowest main-flow local code is above theirs, and neither ancestor has
  a main-flow reach below the branch (`300`'s main flow starts at `300.600588`; `300` has
  reattached segments at local code `300`, which is where the old `ancestor` rule put them); KUSR's
  is the same shape on `800.980217.743026`.
- Ordered sums: all seven float sums that reach `upstream_area_ha` are ordered on a unique key
  (`local`, the level loop, `other`, `total`, the givers' sum, `shared_ha`; `share_ha` itself is a
  product). The picks that feed them end on unique keys: no two tree segments share
  `(blue_line_key, downstream_route_measure)`, `area_side_top` ends on `linear_feature_id`, and the
  midpoint polygon is picked by id. Nothing unordered found, the DO block and the UPDATEs included.
- The `lowest run` logic in `area_reach` changes nothing in this build: no `lower` or `ancestor`
  polygon targets a pair with more than one run. It is not wrong, and no data here can show it
  right or wrong.

**qa_area.sql.** Kind 7 by `s.source != 'mainflow'` selects the 8,431 `pair_side` polygons and no
other today, and its code-side position (the polygon's own codes) is the same whichever rule put a
polygon there. No `pair_side` polygon has a bad local code (0), so kinds 7 and 9 never meet on one
polygon; 19 share polygons have a bad local code and their kind 8 marker carries the raw code
rather than the normalised one, which can only move a segment toward "unexplained". The class CASE
in `qa_area.sql`: no lookup row on the tree points at a missing polygon or lacks an upstream-area
row (0 and 0), so the `!=` on `poly_wscode` meets no NULL. The digit packing holds while a kind has
under 500,000 markers above a segment (numeric division rounds where the quotient is large, so the
margin is half the million the comment states). Province-wide totals, each an upper bound on what
any one segment can have above it: kind 4 is 28,870 lines (of 1,523,004 main-flow lines), kind 2 at
most the 26,690 edge outlets, kinds 7 to 9 are 8,431, 869 and 1,457. Kinds 5 and 6 I did not count.

**qa.sql, each test round 1 changed, defect restored in a rolled-back transaction:**

| defect | tests that print `f` |
|---|---|
| the Skeena's mouth segment NULL on the tree | the basin test; positive area (the old `bool_and()` form of the basin test prints `t` on it) |
| a test side channel below the entry carries the lookup's 5,060,072 ha | the side-channel test; positive area; additive; never decreases |
| a test side channel segment NULL | the side-channel test; positive area; additive |
| one unassigned class NULL | the unassigned-class test |
| one `no stream` relabelled `below the tree` (4 > 3) | the unassigned-class test |
| one `below the tree` relabelled `no stream` (53,209 > 53,208) | the unassigned-class test |
| an unknown class | the unassigned-class test |
| a giver left with 1.8e-15 ha as its whole area | the share test; positive area; additive |
| no shares at all | the share test (floor) |
| no steps across a gap | the share test (floor); additive; steps start at dead ends |

A defect every test passes: the first finding above. NULL members: every area test now counts with
`FILTER` or wraps `bool_and()` in `coalesce(..., false)` beside a `count(*) = 1`; the two scalar
tests give NULL on an empty table, which prints `name|` and fails in `mainflow_tree.sh`.

**ssnbler_check.sh, `final` for every combination** (not killed; killed is 3 or 4 whatever R did):

| R exits | log | `SSNBLER_AREA=0` | `SSNBLER_AREA=1` |
|---|---|---|---|
| 0 | `node errors: N`, and `area: ok` at a line start | 0 | 0 |
| 0 | `node errors: N`, no `area: ok` | 0 | 5 |
| 0 | no `node errors:` line | 5 | 5 |
| 1 | `node errors: N` | 1 | 1 |
| 1 | no `node errors:` line (R's own error before the result) | 5 | 5 |
| 6 | `area: failed` at a line start | 6 (R never exits 6 here) | 6 |
| 6 | no `area: failed` line | 5 | 5 |
| any other | anything | 5 | 5 |

An uncaught R error after the result line would exit 1 and read as a topology failure, but every
statement after that line that can raise is inside the `tryCatch()`, and the outlet argument is
checked as digits by the shell, so there is no route to it. The three mouth ids in
`ssnbler_check.R` are measure 0, edge type 1450, reattached, on 360216952, 360222216 and 360237491.

**Figures against the database** (my own queries; all agree unless said):

- Polygons by method and area: 3,181,977 / 93,747,827; 8,431 / 407,068; 1,754 / 15,985,977;
  20 / 2,128; unassigned 53,208 / 838,859 (667 ha out as shares), 60 / 3,623, 3 / 14; 3,245,453
  polygons, 4,510,368 tree segments.
- Outlets 27,097 summing to 110,143,668 ha, equal to the area assigned; 26,690 at BC's edge, 383
  dead ends (184,499 ha, largest 50,535), 1 cut-off (217), 23 `no_parent`; 184,716 ha above the
  384.
- Steps: 4,483,174 node, 93 junction (90 dead ends, 3 cut-offs), 4 line (cut-offs); depth 4,380.
- Side channels: 360216952 reads 53,122.7 below the entry and 1,681.2 above; 360222215 228,962.1;
  360222216 228,962.1 to 229,062.7; 360237491 302,913.7 to 303,115.7; 87078680 reads 302,610.5 and
  the lookup gives it 4,558,110; the lookup's range on the four is 4,255,363 to 5,111,821.
- Tributaries by their polygons: 51,419.5, 228,942.8, 302,610.5. Basins: Skeena 5,440,478.9 /
  5,440,334.4 (0.0027%), Nechako 4,725,598.1 / 4,725,795.1 (0.0042%), Fraser 23,198,717.8 /
  23,215,086.5.
- Shares: 869 segments, 154,216.9 ha, 494 polygons, median 45.34, largest 37,633.4. Bad-code
  polygons 1,457 / 45,175.4 ha.
- The comparison: 4,362,376 / 4,290,355 / 337 / 72,021 / 71,748; 215,611 rows; one kind 51,293;
  several kinds 41,016; 17 unexplained on 11 lines; every class ceiling in `qa.sql` equals its count.
- `qa.sql`: 2,967,528 touching pairs. Research: 8,111, 71,402 and 2,941 tree segments by lookup
  match; 74,426 split nodes. SSNbler: KLUM under `400` is 24,732 tree segments, the Skeena 261,764.

Three that are marginal, not findings: the Fraser is 0.0705% from its polygons, which the README
gives as "within 0.07%"; "the area build 5.5 min" (README:220, research:64) is not in the record,
which holds 5 min 18 s for the build before round 1 and "about 11" for the build, the comparison,
the tests and the export together; 15 segments carry under 0.001 ha (sliver polygons, the smallest
0.00009 ha), which is "positive" as the README says and too small to mean anything.

## Notes

- 2,435 side-only pairs are on more than one blue line; 632 `pair_side` polygons (20,055 ha, median
  3.1, largest 888) sit on such a pair and go to the side channel with the lowest `blue_line_key`.
  The codes cannot choose between the lines, so this is a tie-break, not a rule; the README's "the
  top one of them" reads as if there were one line.
- A bad-code polygon sits at its stream's mouth pair, and where that pair is on a side channel only
  (the Columbia's `300`, whose mouth pair is on reattached segments) rule 2 would take it. None does
  today.
