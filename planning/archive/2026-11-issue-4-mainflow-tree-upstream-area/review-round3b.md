# Review round 3b (#4): the round 2 fixes (`1aacbf1..55ca8dd`)

Reviewed 2026-11-20 against the build of 55ca8dd in the local database. Every figure below was
measured in that build during this round; every restored defect was inside `BEGIN … ROLLBACK`, and
`fwapg.mainflow_tree_area_polygons` reads as built afterwards (pair 3,181,977, pair_side 8,431,
lower 1,658, range 96, ancestor 20).

## Checklist read

- Index (`checklist_round1.txt`): all 1,199 lines.
- `code-check.md`: the prose of all fourteen H3 sections under `## Mechanisms` (table rows
  skipped), and in full "An ordered dispatch makes severity ordering load-bearing, and nothing
  enforces it" and "Documentation Staleness".
- `code-check-r.md`: "Postgres row order is never fixed unless the query fixes it, so a pick, a
  float sum and a presence check can each depend on it" in full (the `DISTINCT ON` the diff
  reorders). Other headings: index only.
- `code-check-infra.md`: "A SQL function test that cannot fail: pruned columns and a function in
  `FROM`" in full (the new test). Other headings: index only.
- `code-check-shell.md`, `code-check-spatial.md`, `code-check-python.md`: index only; no heading
  names a pattern the 260-line diff uses.

## Verdict

Not clean. Rule 3 (`range`) does what its code says, and 83% of the area it places (936,680 of
1,129,808 ha, 17 polygons) is now on a segment that is not above the segment rule `lower` gave it
before round 2. For the three polygons that hold nearly all of that area, the old segment touches
the polygon and the new one does not. No test notices, the new placement test included.

## The mechanism

**A relation between watershed codes is taken for a place, and whatever a rule was not written
for falls through to the next arm under that arm's name.**

Each rule, each arm of the new test and each class of the comparison is a predicate on codes
(the pair is on a segment, a code sorts into a range, a code is lower, `in_order`). Each is then
described as a fact about position or containment ("those segments lie in it", "the lowest run",
"placed by position"). The two agree where a stream's codes are complete, in order and on one
blue line. The earlier findings are the members for which they are not, each arriving at an arm
that was written for someone else: a NULL member at `bool_and`, a polygon with no segment at the
fallback rules (and so on a side channel), a segment nothing else explains at the last class, a
sum at whatever order the plan gave. Round 2's fix is the same shape. `range` is defined by
elimination (a row of `area_pair_top` that is not exact), it inherits a pick written for rule 1,
and its test arm states the code predicate again.

Where it reaches in this diff, each one checked:

| place | what falls through | measured | finding |
|---|---|---|---|
| `mainflow_tree_area.sql:158-171`, group membership for rule 3 | any main-flow segment whose local code sorts into the range, wherever it is on the line. Rule 1 is anchored by `has_pair`; rule 3 has no anchor | a segment whose local code is not under its watershed code sorts above every polygon code of the stream and joins the last polygon's group (seen on 2 streams); a run below the reach the polygon is coded above (codes out of order) | 1 |
| `mainflow_tree_area.sql:195-198`, the pick | `bottom` is a route measure, compared between runs on different blue lines | rule 1: 1 code pair, 2 polygons, 30 ha have main-flow segments on several lines. Rule 3: 2 polygons, 766,923 ha | 1 |
| `mainflow_tree_area.sql:261-272`, step 5 | `range` is "not exact, and no side pair" | order is right: 193 `pair_side` polygons also have a non-exact row and all are `pair_side` | none |
| `qa.sql:315-338`, the new test | each arm repeats the build's code predicate, chosen by the build's own `method` | 16 restorations below | 2 |
| `qa.sql:378`, ceiling 836 to 878 | `local codes out of order` is given to any differing segment that is not `in_order` and has nothing else | 39 of the 42 new ones are one polygon group moved 11 km by finding 1 | 3 |
| `README.md:57`, `mainflow_tree_area.sql:26`, `research/fwa_mainflow_tree.md:58` | "those segments lie in it" | the segment touches the polygon for 29 of 96 | 1 |
| `README.md:345-346` | "the lowest `blue_line_key`" | 3 of the 632 are not on it | 4 |
| `README.md` and research figures changed by the diff | none | all re-derived and equal (Q5) | none |

## Answers to the questions

**1. `range`.** All 96 are on the top of the run the code calls lowest (recomputed from the
network: 96 polygons, 81 code pairs, 96 on that run's top). None has its pair on any tree
segment. `range` cannot take a polygon whose pair is on a side channel: 193 `pair_side` polygons
have a non-exact row of their own and every one is `pair_side`. No `pair` polygon moved: the old
pick (`WHERE has_pair ORDER BY bottom, blue_line_key`) gives the built segment for 3,181,977 of
3,181,977. "Lowest" is the lowest route measure, though, and for two of the 96 the candidate runs
are on two blue lines (finding 1).

**2. The placement test.** Each arm says what its rule's code predicate says; none is NULL or
false for a polygon placed by its rule (the test prints `t` on the build, and each rule's target
has both codes). It accepts a wrong rule and a wrong place within the codes. Restorations, one
row changed unless said:

| restored | printed |
|---|---|
| nothing | `t` |
| `pair` polygon on a side channel of its stream above its code | `f` |
| `pair` polygon on the main-flow segment of its stream with the greatest local code | **`t`** |
| `pair` polygon on a main-flow segment below its code | `f` |
| `pair_side` polygon on a main-flow segment of its stream | `f` |
| `pair_side` polygon on a side channel with another local code | `f` |
| one `range` polygon back at its `lower` segment, method `lower` (round 2's defect) | **`t`** |
| 95 of the 96 `range` polygons back at `lower` | **`t`** |
| all 96 back at `lower` | `f` (only the `count(range) > 0` floor) |
| `range` polygon on a side channel above its code | `f` |
| `lower` polygon on a side channel below its code (round 1's defect) | `f` |
| `lower` polygon on a main-flow segment above its code | `f` |
| `ancestor` polygon on a side channel of its ancestor | `f` |
| `ancestor` polygon on the ancestor's main flow at or above its branch | `f` |
| a method the test does not know | `f` |
| a polygon on a segment that is not in the tree | `t` (the inner joins drop it; "the outlets' areas sum to the area assigned" covers it in a real build) |

**3. The 42.** Found exactly: 48 `local codes out of order` segments lie below a `range` polygon
or below its old `lower` segment, and 42 of them equalled the lookup with the polygon at `lower`
and are now below the lookup by exactly the polygon's area. 39 are on one line (blue line
360877164, measure 18,179 to 23,930), each 132 ha under the lookup. They are not what the class
says (finding 3). The other 3 segments (57, 57 and 6 ha under the lookup) are the same movement at
small scale: a polygon moved down a line to a run whose codes are out of order. Distance does not
settle which segment is theirs (the new one is nearer for the 6 ha polygon, farther for one 57 ha
polygon, mixed over the three polygons of the other).

**4. The rule lists.** `README.md:50-61`, the SQL header (lines 15-32) and the `CASE` in step 5:
the same five, in the same order (`pair`, `pair_side`, `range`, `lower`, `ancestor`). The comments
on `area_pair_top` and `area_reach` were renumbered with them.

**5. The rest of the diff.** Re-derived and equal: methods table (96 / 1,129,808 and
1,658 / 14,856,168), shares (803 segments, 112,519 ha, 458 polygons, median 46.6, largest 5,690),
Fraser 23,198,718 against 23,215,086 ha (0.0705%, so "within 0.08%" is the right bound and 0.07%
was not), 4,290,356 / 72,020 / 71,747, 215,648 rows and every class count, one kind 51,292,
several kinds 41,016, 632 polygons and 20,055 ha, 158,188 segments. The `DISTINCT ON` ends on
`bottom, blue_line_key`, which is unique within a code pair, so the pick is fixed.

## Findings

- **[severity: bug]** `extras/mainflow_tree/sql/mainflow_tree_area.sql:158-198` and `:261-272`
  (rule 3), with `README.md:55-57`, the SQL header `:23-26` and
  `research/fwa_mainflow_tree.md:58` — a polygon whose pair is on no segment is given to
  main-flow segments because their local code sorts into its range, and for most of the area
  those segments are not where the polygon is.
  - Measured over the 96: the segment touches the polygon for 29 (187,151 ha). For 67
    (942,658 ha) no segment of the run touches it. The segment `lower` gave touches for 11
    (1,089,958 ha). So "those segments lie in it" holds for 17% of the area the rule places.
  - For 17 polygons (936,680 ha) the new segment is not above the old one in the tree, so
    segments that carried the polygon no longer do: 173 segments in all. The three that matter,
    all polygons for land outside BC whose code is one step above the reach they touch:

    | polygon | ha | new segment | what happened | effect |
    |---|---|---|---|---|
    | 1000002557 (BEAV) | 766,913 | 868144441, 77 m from the polygon, on blue line 359024601 | the group has runs on two lines: Beaver River (359572098, bottom at measure 52,637, the connector out of BC directly above the reach the polygon touches) and a 1.46 km unnamed line of edge type 1100 (bottom at 816). `ORDER BY … bottom` compares the two measures and the short line wins | 8 Beaver River segments (1,528 m, measure 51,109 to 52,637) read 924 to 5,333 ha; the lookup has 780,782 to 786,108; the short line reads 767,008 |
    | 1000002001 (TATR) | 105,986 | 201003333, 865 m away | two segments coded `…564934` lie below the reach coded `…563902` on the line (codes out of order), and form the "lowest run" of the range | 4 segments (924 m) between them and the polygon read 59,457 ha; the lookup has 218,038 |
    | 1000003707 (SWIR) | 63,375 | 195005469, 7,349 m away, at measure 329 near the stream's mouth | that segment's local code (`800.901317.630554.425917`) is not under its watershed code, so it sorts above every polygon code of the stream and falls in the last polygon's group | 33 segments (12,082 m) read 54 to 5,258 ha; the lookup has 65,742 to 70,947 |

    The same thing moves 132 ha (1000003435, -36, -37) 11 to 12.5 km down blue line 360877164
    onto a segment coded `700.470473.004305` on stream `700.328291`: 92 segments lose it.
  - Where the rule does what its sentence says: the 29 polygons whose segment touches them, the
    owner's example (blue line 360884436) and the Kettle polygon (146,433 ha, the connector
    inside it) among them. 79 of the 96 have the new segment above the old one in the tree.
  - Tests: the record has all 24 printing `t`; the placement test, run here, prints `t`. In the
    profiles of the three streams area still rises downstream, and their segments already had a
    routing class in the comparison, so the change does not show in either.
  - Two separate causes, for the owner to weigh since the rule was decision 8: the group has no
    anchor (rule 1 has `has_pair`; a likely one here is that the run sits above the polygon's
    `lower` reach in the tree, which holds for 79), and the pick compares measures across blue
    lines (measured exposure in rule 1 is 30 ha, in rule 3 766,923 ha).
  - **Rule:** code-check.md "A proxy is not the property" ; code-check.md "A fixture that cannot reach the failure mode"

- **[severity: fragile]** `extras/mainflow_tree/sql/qa.sql:315-338` — the test added for round 2
  does not fail on round 2's defect, and passes finding 1's placements. It picks its arm by the
  build's own `method` and each arm is the code predicate the rule used, so it can show a polygon
  is on main flow or a side channel and on which side of its code, and nothing about which rule
  should have applied or where in the code range the segment is. Restored: 95 of 96 `range`
  polygons back at `lower` prints `t`; a `pair` polygon on the top segment of the Skeena prints
  `t` (table under Q2). What it does catch, each seen red: any non-`pair_side` polygon on a side
  channel, a `pair_side` polygon off its pair, a polygon on the wrong side of its code, an unknown
  method.
  - **Rule:** code-check.md "Verification that reads its own output" ; code-check.md "Restore the bug and prove the guard fires"

- **[severity: fragile]** `extras/mainflow_tree/sql/qa.sql:378` (ceiling 836 to 878), with
  `planning/active/findings.md:507` — 39 of the 42 segments the ceiling was raised for are the
  132 ha of finding 1: they agreed with the lookup before round 2 and are 132 ha under it now,
  because the polygons were moved below them to a segment 11 km and more from the polygons. The
  class is given to any differing segment that is not `in_order` and has no other class
  (`qa_area.sql:312`), so it took them, and the record's reading ("a polygon placed by position
  on a line whose codes run out of order") is the reverse of what happened: the polygon was
  placed by a code, on a segment whose code is not under its stream's. The count is right; what
  it was read as is not, and it should be re-measured once finding 1 is settled.
  - **Rule:** code-check.md "A proxy is not the property" ; code-check.md "An ordered dispatch makes severity ordering load-bearing, and nothing enforces it"

- **[severity: fragile]** `extras/mainflow_tree/README.md:345-346` (added in this diff) — "goes to
  the one with the lowest `blue_line_key` (632 polygons, 20,055 ha)". The counts are right. The
  order in `area_side_top` is reattached before followed, then `blue_line_key`, and 3 of the 632
  (38 ha) are not on the lowest `blue_line_key` of their pair.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

## How the main figures were taken

- Runs recomputed in temporary tables with the SQL of `area_pair_top` (2,968,039 runs, 830 with
  no segment at the pair), then joined to the built table.
- "Touches" is `ST_Intersects(polygon, segment)`; distances are `ST_Distance`. Control with the
  same query: 2,796 of a 3,000 sample of `pair` polygons touch their segment, 847 of 1,658
  `lower`.
- The `lower` segment of a `range` polygon was taken as the top segment (greatest measure, lowest
  blue line) of the main-flow segments at the greatest local code below the polygon's. All 96
  have one, and the methods table shows all 96 came from `lower`.
- "Not above in the tree" and the lost segments: both segments walked down
  `fwapg.mainflow_tree_area.downstream_id` to the outlet and the two paths compared.
- The 42: tree area with the polygon moved back to `lower` (`upstream_area_ha` less the `range`
  polygons above the segment, plus those above it at `lower`) against the lookup area, at 1e-6
  relative. This ignores the change in length shares (869 to 803 segments), which is why it is stated
  for the `local codes out of order` class only, where it gave exactly 42.
