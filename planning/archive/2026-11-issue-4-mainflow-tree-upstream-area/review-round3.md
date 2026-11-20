# Review round 3 (#4): the branch at 55ca8dd, and round 2's fixes

**Cut short at 19:17Z on 2026-11-20**, on the coordinator's message that the database tables were
about to be rebuilt from a later commit. Everything below was measured between 17:54Z and 19:16Z on
the build from 55ca8dd (tree column checksum `4c1120f5…`, taken at 18:18Z). No measurement was taken
after the message; the one statement run after it was a read of `pg_stat_activity` to confirm that
no session of this review was left open (none was). The checksum was not re-taken at the end.
The checkout's `mainflow_tree_area.sql` and `qa.sql` were changed by another session at 19:18Z. Every
run reported here was generated before that (the last at 19:04Z), and each generated script was
checked afterwards to hold the text of 55ca8dd in every block it did not change.

**Unfinished, and marked so in the table:**

- Four build-rule defects never ran: `pair_lowest_any_run`, `pair_bottom_of_run`,
  `connector_ends_run`, `side_not_only` (rows 13, 15, 17, 18). They were queued behind a statement of
  mine that timed out, and their re-run was stopped by the cut.
- None of the 31 defects written for the stored tables ran (16 on the node pointer, the gap steps,
  local area credited elsewhere and the shares; 15 misplacements across the arms of the placement
  test): rows 2, 3, 5, 7, 11, 12, 35, 37 and 41 to 44 say "not restored" for that reason.
- The three sum tests (additive, never decreases, outlets sum) have **no usable verdict under any
  build-rule defect**. My first harness applied area changes as deltas, and with polygons of 10⁵ to
  10⁶ ha the cancellation in `(x + P) − P` exceeds the tests' 1e-9 tolerance: "never decreases"
  printed `f` even on a defect that only removes area. A second harness that re-sums with the
  build's own arithmetic was written; its no-mutation control was running when the cut came, so it
  has no result at all. What stands from the first harness is said per row.
- The area attribute against `ST_Area` (row 9) was restored only as far as the two polygon-table
  tests.

## Checklist read

- `code-check-infra.md`: in full.
- `code-check-python.md`: in full.
- `code-check.md`: the prose of all 14 headings under Mechanisms (table rows skipped); under "Rules
  that stand alone", "An ordered dispatch makes severity ordering load-bearing, and nothing enforces
  it". Not read: the other 13 stand-alone rules, Security (6), Spreadsheets and PDFs (4): 23 headings.
- `code-check-r.md`: "Postgres row order is never fixed unless the query fixes it, so a pick, a float
  sum and a presence check can each depend on it". Not read: 125.
- `code-check-shell.md`: "psql does not interpolate `:'var'` inside a dollar-quoted string, and
  `\quit N` exits 0"; "`a && b || c` runs `c` when any step before the `||` fails". Not read: 70.
- `code-check-spatial.md`: "FWA `upstream_route_measure` misses the next segment's start"; "FWA main
  flow is not edge type 1000 alone"; "A Freshwater Atlas main stem's downstream end lies on the
  receiving river's centreline, not at the confluence". Not read: 91.

## The mechanism

**The tests were written from the result, and no rule was ever the unit of a test.**

1. Additive at every node, never decreasing down a line, the outlets summing to the area assigned,
   every segment positive, the column equal to the table: each is true of *any* assignment of
   polygons to segments once it is summed. Moving a polygon from one tree segment to another and
   summing again leaves all of them true, and that move is what a placement-rule defect is. So these
   tests cannot see one, by construction (argued, not measured: see the cut above).
2. What is not invariant under a move: the named places (four Skeena side channels, 87078680, the
   Skeena and Nechako mouths), which see a move only if it crosses them; the placement test round 2
   added, whose arms are necessary conditions (the segment's source and which side of the polygon's
   code it is on), so it sees a move across a source boundary or across the polygon's own code and
   none within; and the comparison in `qa_area.sql`, which sees a move only on main-flow segments
   with nothing routed differently above them, only through a ceiling, and only when
   `qa_area.sql` is run again.
3. The rules exist as prose three times (the header of `mainflow_tree_area.sql`, README "Upstream
   area", the plan's decisions) and as joins once. Nothing derives a polygon's expected segment a
   second way. So a rule can reach where it was not meant to (round 1: side channels; this round:
   `range` onto another blue line and down a line), be fixed in one table of two (round 1), be
   incomplete (round 2), or be described more strongly than it reads (round 1: `FWA_Upstream`; this
   round: "those segments lie in it"), with every test green.
4. The two lists that happen to agree are the tests and `08_restore_the_bug.py`. Its 15 cases are
   one or two per test, each changing a stored value the test reads, so "all 15 fire" measures that
   each test reads its table. No case changes a rule, and the list of rules is in neither.
5. A ceiling is re-measured when a rule changes, so a regression that lands in a ceilinged class is
   absorbed by the new count (this round: 42 segments, below).

Every place the mechanism reaches is a row of the enumeration that reads "held by the code alone".

## Findings

- **[severity: bug]** `extras/mainflow_tree/sql/mainflow_tree_area.sql:198`
  (`ORDER BY wscode_ltree, localcode_ltree, has_pair DESC, bottom, blue_line_key`), with `:231` — "the
  lowest run" is decided by comparing route measures taken on different blue lines. `bottom` is a
  run's lowest measure on its own line; two runs of one group on two lines have no order in it. Two
  main-flow code pairs, on one watershed code, are on more than one blue line (2 `pair` polygons,
  30 ha), so the comparison decided little before round 2. Round 2's `range` rule now routes a whole
  cross-border basin in BEAV by it. Polygons 1000002557 (766,912.7 ha) and 1000002520 (10.3 ha), code
  `200.692231.387879.164874`, have three range segments in two runs: 8000082 and 868144441 on blue
  line 359024601 (measure 816 to 1,458) and 868144444 on 359572098 (measure 52,637, a 261 km
  connector). The first run wins because 816 is less than 52,637. As built: line 359024601 (1.5 km)
  reads 766,923 to 767,008 ha; the eight segments of 359572098 from measure 51,109 to 52,637 read
  924 to 5,333 ha and the 261 km connector above them 887 ha (a length share); the two lines meet at
  8000486 (772,341 ha). The lookup gives the eight 780,782 to 786,108 ha. Rule 4 (`lower`), which
  placed these polygons before round 2, has 868144442 as its segment for them (359572098 at measure
  52,495, the reach coded one unit below the polygon), upstream of all eight. That is the rule
  re-derived on the stored tables, not a reading of a build from before round 2. 766,923 of the
  1,129,808 ha the rule moves is this pick. No test sees it: the segments are in routing classes of
  the comparison, which have no ceiling. Offered tentatively: order runs across lines by the tree
  (the run whose water the other's reaches), or leave a polygon whose range spans lines to rule 4.
  - **Rule:** code-check.md "A proxy is not the property"

- **[severity: bug]** `extras/mainflow_tree/sql/mainflow_tree_area.sql:156-198` and `:261-272`
  (`range`, round 2's fix), with `README.md:55-57`, the header at `:23-26` and
  `research/fwa_mainflow_tree.md:58` — for 15 of the 96 polygons (169,757 ha) the rule places the
  polygon *downstream* of where rule 4 placed it, so 165 segments (39 km) that carried it before
  round 2 no longer do. (The parallel reviewer has the premise; these are the parts that may be
  new.) Compared per polygon by walking the stored `downstream_id`: 79 polygons (193,128 ha) went
  up the tree, which is what the rule describes; 15 went down; 2 went to another line (above). Two
  causes:
  - **A segment whose local code is not under its watershed code** sorts above every code on its
    stream in `grouped` (`:164`, `c.localcode_ltree <= s.localcode_ltree` on raw segment codes; step
    3 normalises polygons' codes only), so it becomes the "range" of the stream's highest polygon.
    489 main-flow tree segments have such a code; 5 `range` polygons (63,632 ha) sit on one. SWIR:
    polygons 1000003707 (63,375 ha) and 1000003680 (125 ha), code
    `800.901317.630554.417745.150105`, are on segment 195005469 at measure 329 of blue line
    360884225, whose local code is `800.901317.630554.425917`. Rule 4 puts them at the top of the
    line (195000066, measure 11,934, reach `.150104`). The 33 segments between (measure 583 to
    12,665, 12.1 km) read 54 to 5,258 ha; the lookup gives them 65,742 to 70,947. INKR: three
    polygons (132 ha) at `700.328291.905341`, on a segment coded `700.470473.004305`; 92 segments
    (14.7 km) lost them.
  - **Local codes out of order on the line.** TATR: polygon 1000002001 (105,986 ha),
    `990.295215.563903`, is on 201003333 (blue line 360886456, measure 101,336, local code
    `.564934`). The reach `.563902` lies directly *upstream* of it (four segments, measure 101,426
    to 102,350, 924 m): it reads 59,457 ha, the three below 165,590, and the lookup gives all seven
    about 218,038.

  61 of the 96 are cross-border polygons (ids from 1,000,000,000; 1,127,927 ha); 46 are coded
  exactly one unit above the reach rule 4 gives them to and 14 at `.000001`, which reads as "just
  above this reach" and is what rule 4 does. By midpoint, 32 of the 459 range segments lie in a
  polygon of the code (10 polygons, 154,802 ha, have all their range segments inside; 85 polygons,
  974,989 ha, have none). The share rule already uses that test ("the polygon at its midpoint"), so
  one likely home is to let rule 3 take a polygon only where a segment of its range lies in it;
  the owner's call, as decision 8 was.
  - **Rule:** code-check.md "A proxy is not the property" ; code-check.md "A fixture that cannot reach the failure mode"

- **[severity: fragile]** `extras/mainflow_tree/sql/qa.sql:378` (`'local codes out of order') <= 878`),
  with `README.md:219` and `research/fwa_mainflow_tree.md:66` — the rise from 836 to 878 is 42
  segments on 4 lines that agreed with the lookup before round 2 and are now 5,264 ha below it in
  all, because `range` moved a polygon below them that its code puts above them. Measured two ways
  (the rule taken out in temporary tables; and the walk from rule 4's segment down to the range
  segment): 42 both times, and all 42 are among the 165 above. The class name is true of them, and
  the record's line ("a polygon placed by position on a line whose codes run out of order") is
  accurate, but the ceiling was raised to a count that a regression produced. Ceilings at the
  measured count are the accepted design; this is what that design cost here.
  - **Rule:** code-check.md "Verification that reads its own output"

- **[severity: fragile]** `extras/mainflow_tree/sql/qa.sql:311-338` (the placement test) — its arms
  hold the segment's source and one inequality each, so every part of a rule that chooses *among*
  main-flow segments on the right side of the polygon's code, or among side channels of the pair, is
  held by the joins alone. Restored in temporary tables from the file's own text, applied to the
  stored tables in a rolled-back transaction, all 11 tests that do not read the comparison printing
  `t`:
  - rules 2 and 3 swapped (`range` before `pair_side`): 193 polygons (19,870 ha) leave side channels
    for main-flow range segments, 3,312 segments change area. None of them agrees with the lookup
    now, so the comparison's ceilings would not move either: nothing anywhere holds this order.
  - rule 1's lowest run that holds the pair, made the highest (round 1's fix): 43 polygons
    (1,085 ha), 805 segments change. 192 of those agree with the lookup now, so the comparison is
    its only guard, after a re-run of `qa_area.sql`.
  - rule 2's "top one of them", made the bottom: 2,163 polygons (79,570 ha), 3,180 segments. Its
    lowest blue line, made the highest: 629 polygons (20,017 ha). Reattached before followed,
    reversed: 5 polygons (79 ha). All on side channels, which the comparison never limits.

  Also accepted by an arm, read from the test and not restored (the per-arm cases did not run): a
  `pair` polygon on any main-flow segment of its stream above the next polygon's code (the arm has
  no upper bound), and a `range` polygon relabelled `pair`.
  - **Rule:** code-check.md "A proxy is not the property" ; code-check.md "Restore the bug and prove the guard fires"

## The enumeration

How each row was restored: steps 3 to 5 and 8 of `mainflow_tree_area.sql` were run from the file's
text into temporary tables with one change, the polygons that land elsewhere were moved in
`fwapg.mainflow_tree_area_polygons` inside `BEGIN … ROLLBACK`, and `qa.sql`'s 11 area tests that do
not read the comparison's tables were run. Control: with no change, 0 of 3,245,453 polygons moved,
the unassigned table was identical and all 11 printed `t`. (Step 5 was split so its lateral ran only
for the polygons that reach it; the control is what shows the split equal.) "Placement" is the test
`every polygon is on a segment its rule allows…`; "unassigned" is `every unassigned polygon has a
class…`. Per the cut: a `t` from all 11 stands; an `f` is reported only from tests that read the
polygon tables or count exact zeros; the three sum tests are "no verdict".

| # | rule or invariant (where stated) | test in `qa.sql` that fails | how I know | held by |
|---|---|---|---|---|
| 1 | one tree segment per upstream node (step 1) | none | not restored: needs the build | the build's unique index |
| 2 | a step by node goes to the segment whose upstream node is this one's downstream node (header, step 2) | "area is additive" by its design (inflow from geometry) | not restored (case written, not run). 08 changes one area value, not a pointer | test, unproven against a pointer |
| 3 | a `line` or `junction` step lands on the nearest tree segment lower on the line, or on the first line of the path with one (header, README Gaps, decision 4) | none expected: the additive test reads these steps from the table, and `gap` is a routing class with no ceiling | not restored (two cases written, not run) | the code alone, as far as read |
| 4 | the 1 mm tolerance on a junction measure (step 2) | none | not restored: needs the build | the code alone |
| 5 | where the paths lead to no tree segment the segment is an outlet: 383 dead ends and 1 cut-off (header, decision 4) | "steps across a gap start at dead ends and cut-offs only" (ceilings 383, 1), "at most 97 steps" | not restored here; round 2 restored "no steps across a gap" | tests |
| 6 | every segment is reachable from an outlet, or the build stops (step 6) | none | not restored: needs the build | the build's exception |
| 7 | a step is recorded by method (decision 4) | "steps across a gap start…" | 08 case 7 (a node step labelled `junction`): fires. The reverse (a gap step labelled `node`) written, not run | test, one direction proven |
| 8 | each polygon goes to one segment (header) | none | not restored | the primary key on the polygon table |
| 9 | a polygon's area is `ST_Area`, not the `area_ha` attribute (step 3, decision 6) | not established | restored as far as it went: 3,240,636 polygons' areas differ in the last bits, too many for the harness, so only placement and unassigned ran: both `t`. Measured beside it: the attribute equals `ST_Area` to 0.00000% on the Skeena, the Nechako and the three test tributaries, and is NULL for the 2,053 cross-border polygons (16,178,419 ha), so the basin and side-channel tests could not tell | not established |
| 10 | a polygon with no local code, or one not under its watershed code, sits at its stream's mouth (step 3, README) | placement; unassigned | restored (`bad_code_kept`): 1,464 polygons move, 9 are left unplaced with no class. Both printed `f`. The test repeats the build's own normalisation, so it holds the rule against being dropped, not against being wrong. 0 polygons have no local code: that arm has no data | tests |
| 11 | rule 1: a main-flow segment of its watershed code at or above its local code (header, README, decision 6.1) | placement, arm `pair` | read from the arm; the per-arm cases did not run. 08 case 11 moves a `lower` polygon, not a `pair` one | test, unproven for this arm |
| 12 | rule 1: below the next local code that has a polygon | none: the arm has no upper bound | read; not restored | the code alone; the comparison |
| 13 | rule 1: the top of the run | not established | **not restored** (`pair_bottom_of_run` did not run) | not established |
| 14 | rule 1: the lowest run that holds the pair (step 4; round 1's fix) | none | restored (`pair_highest_run`): 43 polygons, 1,085 ha; all 11 `t` | the comparison only (192 changed segments agree with the lookup now) |
| 15 | rule 1: a run that holds the pair itself, not any run of the group (step 4, research; the header and README say only "the lowest run") | not established | **not restored** (`pair_lowest_any_run` timed out, a statement of mine). So how many polygons the header's wording would place differently is not measured | not established |
| 16 | rule 1: a reach with no polygon of its own takes the polygon below it (the run) | "every tree segment has a positive upstream area"; in a build, the 803 share ceiling | restored (`pair_plain_reach`): 23,897 polygons (3,989,156 ha) move and 18,124 segments are left at zero. The harness does not redo length shares; a build would give them shares | tests |
| 17 | step 4: a connector with no local code does not end a run | not established | **not restored** (`connector_ends_run` did not run) | not established |
| 18 | rule 2: only where the pair is on no main-flow segment | not established | **not restored** (`side_not_only` did not run) | not established |
| 19 | rule 2: the top one of them | none | restored (`side_bottom`): 2,163 polygons, 79,570 ha; all 11 `t` | the code alone |
| 20 | rule 2: reattached before followed (step comment, decision 6.2) | none | restored: 5 polygons, 79 ha; all 11 `t` | the code alone |
| 21 | rule 2: then the lowest blue line (README caveat, decision 6.2) | none | restored: 629 polygons, 20,017 ha; all 11 `t` | the code alone |
| 22 | rule 3 exists (decision 8) | placement, by its floor `count(range) > 0`; positive area | restored (`no_range`): 96 polygons to `lower`, 67 segments at zero. The floor is the whole guard: a build that lost only some range polygons would pass it | tests, by a floor |
| 23 | rule 3: the lowest run of the range | positive area in the harness, through 2 segments; in a build those take shares and 805 > 803 is what would fire | restored (`range_highest_run`): 5 polygons, 767,055 ha. No test reads where a `range` polygon is | the share ceiling, by 2 segments |
| 24 | rule 3 comes after rule 2 (header "in order") | none | restored: 193 polygons, 19,870 ha; all 11 `t` | the code alone |
| 25 | rule 3: "those segments lie in it" (header `:26`, README `:57`, research `:58`) | none | measured, not a defect to restore: 32 of 459 by midpoint | a sentence |
| 26 | rule 4: the greatest local code at or below | placement and unassigned, when it reads reaches above instead (`lower_above`: 1,664 polygons, 20 with no class). When it takes the least code (`lower_least`: 820 polygons, 14,618,680 ha): placement `t`, sum tests no verdict | restored, both | "at or below": tests. "Greatest": the comparison (11,911 changed segments agree with the lookup now) |
| 27 | rules 4 and 5: the top segment of the reach | placement `t`; sum tests no verdict | restored (`reach_bottom`): 659 polygons, 1,732,595 ha | the comparison (1,111 segments) |
| 28 | rules 4 and 5: the lowest run of the pair (round 1's fix in `area_reach`) | none can | restored (`reach_highest_run`): 0 polygons move. No data reaches it, as round 2 found | no data |
| 29 | rules 4 and 5 read main-flow reaches only; only rule 2 gives a polygon to a side channel (header, README, decision 8) | placement | restored (`reach_any_source`): 8,576 rows change, 687 to another segment; printed `f`. Also 08 case 11 | test |
| 30 | rule 5: the nearest ancestor | placement `t`; sum tests no verdict | restored (`ancestor_farthest`): 9 polygons, 1,251 ha | the comparison (847 segments) |
| 31 | rule 5: strictly below the branch's code | placement | restored (`ancestor_at_branch`): 5 polygons; printed `f` | test |
| 32 | rule 5: the greatest local code | placement `t`; sum tests no verdict | restored (`ancestor_least`): 19 polygons, 2,054 ha | the comparison (382 segments) |
| 33 | rule 5 exists | placement (floor); unassigned (20 with no class) | restored (`no_ancestor`); both printed `f` | tests |
| 34 | an unplaced polygon has a class: `999`, `no stream`, `below the tree` (header, README, step 8) | unassigned | 08 case 6; round 2's three relabellings; rows 10, 26 and 33 here | test |
| 35 | a segment's local area is the polygons given to it (step 6) | none expected: the placement test reads the polygon table, never `local_area_ha`, and the sum tests hold for any local area | not restored (two cases written, not run) | the code alone, as far as read |
| 36 | a segment's area is its local area plus what flows in (step 6) | "area is additive" | 08 case 3 | test |
| 37 | nothing lost or added: the outlets sum to the area assigned | "the outlets' areas sum…", within 1e-9 of the province (0.11 ha) | 08 case 5 (+1,000 ha). A polygon under 0.11 ha counted twice passes by the arithmetic; case written, not run | test, above 0.11 ha |
| 38 | every sum in a fixed order: two builds agree to the last bit (step 6, README) | none | not restored: needs two builds. The record holds the checksums | the code alone |
| 39 | the tree's column is the area table's (step 9) | "every tree segment has a positive upstream area" | 08 case 2 | test |
| 40 | the column is added only where missing (step 9) | none | not a property a test of the data can hold | the code alone |
| 41 | a segment with nothing above it takes a share (header, decision 7) | positive area | row 16 shows the test sees a segment at zero; the direct case did not run | test |
| 42 | the share is of the polygon at the segment's midpoint, the nearest within 500 m | none expected | not restored | the code alone, as far as read |
| 43 | the share is in proportion to length against all tree segments in the polygon | none expected: the share test counts rows | not restored | the code alone, as far as read |
| 44 | the share is taken from the segment the polygon was given to | "the outlets' areas sum…" expected | not restored | test, unproven |
| 45 | a giver keeps what is left, never noise as its whole area | "at most 97 steps… 803 segments given a length share" | round 2 (a giver left with 1.8e-15 ha) | test |
| 46 | at most 97 steps across a gap, 803 shares | the same test | 08 case 12 | test |
| 47 | plain main flow agrees with the lookup (README; the three tests on `fwapg.mainflow_tree_area_qa`) | the three comparison tests | 08 cases 13 to 15 change the comparison's table. A defect in the build reaches these tests only through a re-run of `qa_area.sql`, which this review could not make. Every "the comparison" in the last column means this | the comparison in `qa_area.sql` |
| 48 | the four Skeena side channels, 87078680, the Skeena and Nechako mouths | their three tests | 08 cases 8 to 10 | tests |

**`08_restore_the_bug.py` against this table.** Its 15 cases reach rows 7, 29, 34, 36, 37, 39, 46,
47 and 48, and in each it changes a stored value, not the rule. It does not reach rows 1 to 6, 8 to
28, 30 to 33, 35, 38 and 40 to 45: every placement rule but "not on a side channel", the gap steps'
targets, the local area, and the shares' size and source.

## Asked

- **Is each `range` polygon on the top of the lowest run of its group?** Yes, all 96, re-derived
  from the source tables with no use of the build's temporary tables: 81 codes, 83 runs, 2 codes
  with more than one run. 8 range segments are in runs not taken. "Lowest" is the pick the first
  finding is about.
- **Can `range` take a polygon whose exact pair is on a side channel?** Not as written (`sd` is
  joined on `m.exact IS NOT TRUE` and tested first), and 0 of the 96 have their pair on any tree
  segment. But 193 `pair_side` polygons also have main-flow segments in their range, and no test
  holds which rule takes them (row 24).
- **The 42 new "local codes out of order" segments.** They are what the class says, and they are
  new differences: the third finding.
- **The placement test's arms.** Each says less than its rule (fourth finding). None can be NULL
  for a correctly placed polygon: a run's top segment always has a local code, and a NULL arm or an
  unknown method counts as a failure. Wrong placements it accepts: rows 14, 19 to 21, 23, 24, 26 (the least code), 27, 30 and 32, each
  restored; row 12, read.
- **README's rule list and the header's.** The same five rules in the same order, and step 5's CASE
  takes them in that order. Neither says "the run that holds the pair itself", which the step 4
  comment, the research file and the code do (row 15, not measured).

## Figures against the database

Re-derived with my own queries at 18:18Z and all agree with README and the record: polygons by
method; unassigned 53,208 / 838,859 ha (667 out as shares), 60 / 3,623, 3 / 14; 27,097 outlets
summing to 110,143,668 ha; steps 4,483,174 by node, 93 by junction (90 dead ends, 3 cut-offs), 4 by
line; 383 dead ends (184,499 ha, largest 50,535) and 1 cut-off (217) as outlets; shares 803
segments, 112,519 ha, 458 polygons, median 46.6, largest 5,690; 1,457 bad-code polygons (45,175 ha);
the comparison 4,362,376 / 4,290,356 / 337 / 72,020 / 71,747, 215,648 rows, every class count,
17 not explained on 11 lines; the side channels' readings; Skeena 5,440,478.9 against 5,440,334.4,
Nechako 4,725,598.1 against 4,725,795.1, Fraser 23,198,717.8 against 23,215,086.5 (0.0705%); 632
`pair_side` polygons (20,055 ha) on a pair several side channels share.

One figure differs, in the plan only (not under review): decision 8's "459 main-flow segments
(837 km)". The 459 segments I count sum to 540 km, 261 km of it the Beaver's connector.

## Notes

- 1,658 `lower` polygons hold 14,856,168 ha, most of it cross-border polygons: rule 4 is where the
  land outside BC enters the tree, not a remainder.
- Two of my own runs stopped at the 120 s statement timeout before any result (step 5 as one
  statement; a wrapper round step 8), and a third lost four queued defects to a slow statement of
  mine. Each was reshaped to fit the timeout, which was left as set.
- Harness and result files are in the session's scratch directory, outside the repo.
