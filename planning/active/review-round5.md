# Review round 5 (2026-11-20, 21:12Z to 21:26Z)

Scope: `git diff 6dcacac..bc44439 -- . ':(exclude)planning'`, read against the checkout at bc44439 and the
database built from it. Read-only, bar one `BEGIN; UPDATE; ROLLBACK;` to restore a defect for the new test.
No file in the checkout was edited but this one. SSNbler: function source read, and `afv_edges` re-run on a
scratch copy of the finished `lsn_trib_area` files (3,190 edges, 5 s); no landscape network was built.

## Checklist read

- Index (`checklist_round1.txt`): all 1,199 lines, every file's headings.
- `code-check.md`: the prose of all fourteen H3 sections under `## Mechanisms` (table rows skipped). Of
  "Rules that stand alone", the index lines only.
- `code-check-r.md`, full sections: "`match()` treats NA as a matchable VALUE", "`ifelse()` with an all-NA
  test returns a logical vector", "`tryCatch()` nests its handlers", "`unlist()` prefixes a `split()` group's
  name", "A scalar helper called from `glue()` or `mutate()` recycles" (for the row-order rule the
  Mechanisms cite). Index lines only for the rest.
- `code-check-shell.md`, full section: "psql does not interpolate `:'var'` inside a dollar-quoted string".
- `code-check-infra.md`, full section: "A SQL function test that cannot fail". Index lines only for the rest.
- `code-check-python.md`, `code-check-spatial.md`: index lines only; nothing in the diff uses them beyond
  the midpoint test, which is accepted.

## Findings

- **[severity: fragile]** `extras/mainflow_tree/sql/mainflow_tree_area.sql:306-310` (the comment on rule 3),
  with the same claim at `:31-32`, `README.md:58-59` and `:70-71`, `sql/qa.sql:340-341` — "main flow before
  a side channel" is tested only inside the polygon's code range, and the text says more than that. This is
  the round 1 to 4 mechanism once more, in a narrower place: *no main-flow segment in the polygon's code
  range lies in it* is taken for *no main-flow segment lies in it*.
  - What the code does: `area_lift` reads `area_above` (main-flow segments with no polygon of their own
    code, joined on `grp`, the greatest polygon code at or below theirs). A main-flow segment that lies in
    the polygon but has a polygon of its own code, or sits past the next polygon code, is not a candidate,
    so `area_side_hit` then gives the polygon to the side channel.
  - Measured (each `pair_side` polygon against every tree segment whose midpoint is inside it): of the
    1,824 `pair_side` polygons, 1,181 (80,415 of 98,338 ha) hold the midpoint of at least one main-flow
    segment. For 1,177 that is another stream's main flow only (a tributary crossing the polygon on its way
    to the side channel: 873 polygons hold a main-flow segment whose local code equals the polygon's), and
    giving those to the side channel looks right. **4 polygons (2,478 ha) hold main flow of their own
    watershed code** and are on a side channel:

    | polygon | group | ha | own-stream main flow inside | side channel of its pair inside |
    |---|---|---|---|---|
    | 7706821 | BABL | 2,323.5 | 10 segments, 5,506 m (local codes .605612 to .635413; the next polygon code is .598458) | 1 segment, 1,808 m |
    | 7705307 | REVL | 145.0 | 1 segment, 1,640 m | 2 segments, 2,393 m |
    | 8532642 | COAL | 5.8 | 1 segment, 117 m | 3 segments, 435 m |
    | 7553509 | KHOR | 3.9 | 3 segments, 232 m | 8 segments, 578 m |

  - 7706821 is a Babine Lake polygon (waterbody 329026676, code 400.536025.598254). It sits on 4020241, the
    top segment of reattached line 360225340, which reads 2,370.3 ha, 2,323.5 of them this polygon. The
    24 reattached segments below carry it down to where the line rejoins the Babine (4021058, measure
    156,343); the main flow inside the polygon is at measures 159,726 to 167,586 of the same river. Left to
    rules 4 and 5 the polygon would be `lower` on 4021174 (main flow, 497,256 ha), so 3 main-flow segments
    read 0.47% low and 24 side-channel segments read 2,323.5 ha high. It is the shape of round 4's
    polygon 9941495 (48 m of side channel against 18 km of main flow), smaller, and not reached by that fix
    because its main flow is outside its code range.
  - Why no test or enumeration sees it: each of the 4 is on a segment that lies in it, which is all
    `qa.sql`'s geometry test and round 4's table ask. Nothing asks what else lies in a `pair_side` polygon.
  - As the text stands it gives a different answer from the database in three places: the rule 3 comment
    ("and that no main-flow segment lies in": true of 643 of 1,824), "a polygon that holds both is the
    river's" (4 exceptions on the polygon's own stream), and "the polygons it alone lies in" (1,181 also
    hold main flow; 100 hold side-channel segments of several lines, which the README does say).
    `README.md:359-361` ("it stays with the river unless a side-channel segment's midpoint is inside the
    polygon") also predates the swap: polygon 9941495 now has one inside and stays with the river.
  - Two ways it could go, for the author to weigh: word the rule as it is built ("no main-flow segment in
    its range lies in it", with the 4 polygons and 2,478 ha stated as a limit), or have rule 3 skip a
    polygon that any main-flow segment of its own watershed code lies in, which sends these 4 to rules 4
    and 5. Either way a test that counts `pair_side` polygons holding own-stream main flow (4 now) would
    hold the number.
  - **Rule:** code-check.md "A proxy is not the property" ; code-check.md "A guard that fails toward pass"

Nothing else in the diff is a finding. What was checked, by question:

## 1. `ssnbler_check.R`, the plain-arithmetic check

- **Against SSNbler's definition.** `get_segment_pi` gives an edge its area over the areas of the edges
  that share its `tonode`; `afv_edges` multiplies those down the path to the outlet. With no edge flowing
  into two (the script exits 1 before the area step otherwise) "same `tonode`" and "same `toedge`" are the
  same grouping for every edge that is not an outlet. Re-run on the tributary network: SSNbler's `afvArea`
  and the script's `expected` differ by at most 3.9e-16 (2.8e-15 relative), `areaPI` and `share` by 0, in
  280 passes of the loop.
- **The loop ends.** Each pass fills at least one NA or stops. A value could stay NA while `ready` stayed
  true only if `share` were NA for an edge with a `toedge`, which needs an area that is not finite and
  above zero (refused at line 124) or a `tapply` name that misses. Hand-made cases: one edge with an empty
  relationships file (`toedge` reads as logical, all NA) gives 1; two outlets give 1 and 1; a cycle or a
  `toedge` that is not an edge leaves NA and the script stops on `anyNA(expected)`.
- **NA in `to`** is an outlet: `match(NA, edges$rid)` is NA since no `rid` is NA, `share` and `expected`
  are 1. Two edges ending at one outlet node would make SSNbler's share differ from 1, and the script would
  stop; the relationship count at line 103 exits first.
- **Alignment.** `a` is read again from the frame `afv_edges` returns (line 143), as are `rid`, `afvArea`
  and `areaPI`, so a reorder inside `merge(sort = FALSE)` moves all four together. On the tributary
  network the order did not change.
- **`tapply(a, to, sum)[as.character(to)]`.** The names are `as.character()` of the factor's levels, the
  same call as the index. `to` is integer here (`read.csv`). As doubles the lookup holds for ids of 100,000
  to 500,000 (both sides spell `1e+05`) and breaks only where two ids share 15 significant digits.
- Noted, not a finding: the comparison is absolute, 1e-9. Measured agreement is 3e-15 relative, so the
  tolerance decides nothing today; on the smallest KLUM value (1.29e-07) it is 0.8% of the value, and a
  subset whose values go below 1e-9 would pass those edges whatever SSNbler returned.

## 2. The new test in `qa.sql`

- It computes what its comment says: 16,745 places, 15,864 under a fifth, median 0.502%; prints `t`.
- Empty or half-built: one row always (an aggregate, no `GROUP BY` at the top). An empty table fails the
  10,000 floor; a NULL area makes the share NULL, which fails both filters; a zero sum raises.
- Restored defect: with the lookup's area written onto the 58,036 reattached and followed segments that
  have one (rolled back), the test prints `f`: 760 of 16,745 under a fifth, median 0.5000, the three
  literal segments at 0.517, 0.512 and 0.502. After the rollback it prints `t` again.
- The three ids: 123043588 (line 360216962), 87082084 (360222216) and 87078272 (360237491) are each
  `reattached`, step down by `node` into a main-flow segment of the Skeena (360887278), with one other
  inflow, the Skeena's. Shares 1.04%, 4.77% and 6.64%. 123041439 flows into reattached 123041497 with no
  other inflow, as the commit says.

## 3. The swap in `mainflow_tree_area.sql`

- A polygon whose pair is on a main-flow segment stays `pair`: the `CASE` keeps the method, and no
  `range` or `pair_side` polygon in the database has its pair on a main-flow tree segment (0 of 1,836).
- All 12 `range` polygons are on main flow and all 1,824 `pair_side` on a reattached segment, every one
  with the segment's midpoint inside the polygon.
- README, SQL header and code agree on the order: pair, range, `pair_side`, lower, ancestor. The
  tie-breaks in the text are the `ORDER BY`s.

## 4. The `DO` block in `qa_area.sql`

- A marker's number is 1 to 2^48, so fewer than 2^16 markers of a kind keep that kind's sum under
  65,535 x 2^48 = 2^64 - 2^48, inside its slot; each marker is summed at most once per segment on either
  side. That is the right pair of conditions for no carry between slots and no two markers standing in for
  each other. Distinct numbers do not make every subset sum distinct; that stays a matter of odds
  (about 2^-48 a comparison), and a false match would show as an unexplained segment, which the test
  counts.
- The first 3,000,000 row numbers give no repeated 48-bit prefix (the 40-bit one repeats 8 times). The
  largest kind that can be counted without running the script, lines whose mouth is on a side channel,
  has 28,870 markers.

## 5. Figures against the database

All agree: methods (`range` 12, 164,282 ha; `pair_side` 1,824, 98,338 ha; `pair`, `lower`, `ancestor` and
the three unassigned classes as printed); 100 `pair_side` polygons, 3,226 ha, with side segments on several
lines; bad-code polygons 1,435 on a mouth reach, 19 up their line, 3 `ancestor`; shares 1,898 segments,
181,075 ha, 1,116 polygons, median 13.7 ha, largest 37,633 of a 42,667 ha polygon; polygon 9941495 is
9,674 ha, `range`, holds a 48 m reattached segment of its pair and 18,027 m of its own main flow, and 76
main-flow segments lie between its segment and where the side channel rejoins; 27,097 outlets summing to
110,143,331 ha; steps 4,483,174 by node, 93 by junction, 4 by line; the comparison's classes sum to
217,655 as the README has them, and `mainflow_tree_area_qa` carries the area table's values on every row.

Not verified: the KLUM figures in the README's SSNbler section (runs in progress, to be replaced).
