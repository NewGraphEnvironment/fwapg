# Review round 4 (#4): the round 3 fixes, by enumeration

Reviewed 2026-11-20, 20:17Z to 20:41Z, against commit 6dcacac and the build in the database (column
checksum starts `c0b270f3`, the one `findings.md` records for "The build after round 3"). Every count below
is from my own queries over all 3,245,453 rows of `fwapg.mainflow_tree_area_polygons`, not from the repo's
tests. Nothing was committed, created or altered outside temporary tables; the two restored defects ran in
transactions that were rolled back, and the three rows touched read as built afterwards.

## Checklist read

- Index (`checklist_round1.txt`): lines 148 to 1199 in full (Python, R, shell, spatial, `code-check.md`);
  lines 1 to 147 (the infrastructure index) as headings only, since I read that file's full text.
- `code-check-infra.md`: in full (550 lines).
- `code-check-python.md`: in full (206 lines).
- `code-check.md`: the prose of all fourteen H3 sections under `## Mechanisms` (lines 38 to 1347 with the
  table rows removed), and the full sections "An ordered dispatch makes severity ordering load-bearing, and
  nothing enforces it" and "Documentation Staleness".
- `code-check-r.md`: the full section "Postgres row order is never fixed unless the query fixes it, so a
  pick, a float sum and a presence check can each depend on it" (the diff has three `DISTINCT ON` picks).
- `code-check-spatial.md`: the full sections "FWA `upstream_route_measure` misses the next segment's start",
  "FWA main flow is not edge type 1000 alone" and "A Freshwater Atlas main stem's downstream end lies on the
  receiving river's centreline, not at the confluence".
- `code-check-shell.md`: index lines only; the diff under review changes no shell.

## The enumeration

**The claim holds on every row.** Every polygon that is not at the place its codes give is on a segment
whose midpoint is inside it, and every other polygon is at the place its codes give.

| method | polygons (ha) | at its code position | elsewhere | of those elsewhere: midpoint inside | of those elsewhere: segment does not touch |
|---|---|---|---|---|---|
| `pair` | 3,181,977 (93,747,827) | 3,166,110 | 15,867 (3,547,842 ha) | 15,867 | 0 |
| `pair_side` | 1,825 (108,013) | 0 | 1,825 | 1,825 | 0 |
| `range` | 11 (154,608) | 0 | 11 | 11 | 0 |
| `lower` | 8,332 (16,130,088) | 8,332 | 0 | | |
| `ancestor` | 20 (2,128) | 20 | 0 | | |
| unassigned | 53,288 (842,833) | 53,288 (no rule gives a segment) | 0 | | |

For the polygons at their code position, by geometry (not part of the claim, for the record):

| method | at code position | midpoint inside | touches, midpoint outside | does not touch |
|---|---|---|---|---|
| `pair` | 3,166,110 | 2,819,419 | 157,031 | 189,660 (5,780,373 ha) |
| `lower` | 8,332 | 5 | 847 | 7,480 (669,473 ha) |
| `ancestor` | 20 | 0 | 0 | 20 (2,128 ha) |

**How the code position was verified.** I re-derived it from `fwa_watersheds_poly` and the tree's segments
with queries written from the rules, not copied from the build:

- A polygon's local code is its own where it is under its watershed code, else the watershed code.
- Reaches: main-flow segments with a local code, cut into runs of equal (watershed code, local code) along
  each blue line (a gaps-and-islands numbering, not the build's `lag`). Per pair: the line with the most
  main-flow segments of the watershed code, then the lowest blue line key, then the lowest run; its top
  segment. 3,006,206 pairs; 14 have more than one run and 2 are on more than one line.
- `pair`: the reach with the polygon's pair. `lower`: the reach on its watershed code at the greatest local
  code at or below its own. `ancestor`: the nearest ancestor code with a reach strictly below the branch.
  Polygons with no watershed code or under `999` get none unless their pair is on a reach (none is: no tree
  segment is under `999`).
- Result against the build: 3,166,110 + 8,332 + 20 + 53,288 identical; the other 17,703 differ, and they are
  exactly the lifted `pair`, the `pair_side` and the `range` polygons. Their code positions would be: `pair`
  15,867 at their reach top; `pair_side` 1,817 `lower`, 1 `ancestor`, 7 none; `range` 11 `lower`.

**The polygons that are elsewhere, re-derived too.** I rebuilt the candidates (63,157 main-flow segments
whose own pair has no polygon, 55,609 of them with a polygon code below them; side-channel segments whose
pair is on no reach), tested every candidate's midpoint against every polygon of its code (45,445 main-flow
hits in 16,180 polygons; 2,446 side-channel hits in 1,825 polygons) and applied the rules in the README's
order. The segment and the method I get equal the build's for all 3,245,453 polygons. So no polygon that a
rule should have moved was left, and none sits lower than the highest segment its rule allows.

One limit of this: where I had to pick a tie-break (which line, which run, which side channel) I used the
one the code documents, so agreement there says the build does what it says, not that the tie-break is the
right one.

## Findings

- **[bug]** `extras/mainflow_tree/sql/mainflow_tree_area.sql:281-296` (with `303-322`) — rule 2 runs before
  rule 3, and for the one polygon where both apply it puts 9,674 ha on a 48 m side-channel segment while
  19 km of main flow (76 segments) reads about 9,400 to 12,000 ha less than the lookup.
  - Polygon 9941495 (TATR, watershed code `990.295215.193076`, local code `…515369`, 9,674 ha). Its exact
    pair is on one tree segment: 201050174, reattached, 48 m, on blue line 360235662. 61 main-flow segments
    of blue line 360877680 (measures 20,998 to 38,509, 18.0 km, none with a polygon of its own code) have
    their midpoint inside the same polygon.
  - `area_side_hit` takes the polygon first, and `area_lift` then skips it (`p.method IS DISTINCT FROM
    'pair_side'`). The side-channel segment reads 9,705 ha, of which 555 ha enters it and 9,150 ha is this
    polygon. The side channel rejoins the main flow near measure 19,704.
  - Above that point the main flow never receives the polygon: the 61 segments inside it read 33 to
    2,684 ha where the lookup has 12,063; the next 15 segments down (measures 19,704 to 20,998, 14 of them
    with a polygon of their own code) read 2,684 to 2,724 ha where the lookup has 12,766 to 12,943. Below
    the rejoin the main flow reads 12,543 ha.
  - Either other rule would have kept the area on the main flow: rule 3 gives the highest of the 61
    segments, rule 4 gives 201049119 (measure 20,836).
  - No test sees it. The placement test and the geometry test pass, because the side-channel segment does
    lie in the polygon. The comparison classes the 61 as "lookup polygon at another local code" and the 14
    as "side channel, side polygon, share", so each has a class and none is counted as unexplained.
  - It is the only polygon with both a side-channel hit and a main-flow hit, so a change of order (or
    "rule 2 only where no main-flow segment of its range lies in it") moves this polygon and no other. The
    order matches the README, so this is the rule's result, not a slip in the SQL; which rule should win is
    the owner's call. `findings.md` lists "the order of rules 2 and 3 where both could apply" as held by the
    code alone, without this measurement.
  - **Rule:** code-check.md "A proxy is not the property" ; code-check.md "An ordered dispatch makes severity ordering load-bearing, and nothing enforces it"

- **[fragile]** `extras/mainflow_tree/README.md:70` (also `sql/mainflow_tree_area.sql:130`,
  `sql/qa_area.sql:28-31`) — "A polygon with no local code, or with one that is not under its own watershed
  code, sits at its stream's mouth" is not true of 22 of the 1,457.
  - 1,435 (43,028 ha) are on a mouth-reach segment. 19 (2,077 ha, the largest 924 ha) were lifted by rule 1
    from the mouth reach to a segment up the line whose midpoint is inside them. 3 (70 ha) are `ancestor`.
  - The lift is consistent with the geometry rule, so the placement may well be what is wanted; the
    sentence, the SQL comment and the `bad code` kind's description say otherwise. No polygon has a NULL
    local code and a segment.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

- **[fragile]** `extras/mainflow_tree/README.md:208-209` — "the largest 37,633 ha, in a cross-border polygon
  that size" disagrees with the database: the polygon (9693044, BARR, `pair`) is 42,667 ha.
  - The share goes to one 18.8 km main-flow segment (6027463) on the polygon's own watershed code. Whether
    the polygon is cross-border I did not check.
  - **Rule:** code-check.md "One fact derived twice"

- **[fragile]** `extras/mainflow_tree/README.md:50-56` and `sql/mainflow_tree_area.sql:278-302` — three
  things the picks do that the text does not say, one of them exercised.
  - Rule 2, several side channels: 317 `pair_side` polygons have more than one side-channel segment of
    their pair lying in them, 100 of them (3,226 ha) on more than one blue line. The pick is reattached
    before followed, then the lowest blue line key, then the highest measure. The README says "the top one
    of them"; the limit that used to state the lowest-key choice ("632 polygons, 20,055 ha") was removed in
    this diff and nothing replaced it.
  - Rule 3, several lines: `area_lift` orders by blue line key first, so across lines the lowest key wins,
    not the highest segment. Stated nowhere. Not exercised: all 11 `range` polygons have their candidate
    segments on one line.
  - Rule 1, "through reaches with no polygon of their own code": the code does not require the reaches in
    between to have no polygon, only the landing segment. 10 lifted polygons (141 ha) pass a main-flow
    segment whose own pair has a polygon (local codes out of order). All 10 land on a segment that lies in
    them.
  - **Rule:** none

- **[fragile]** `extras/mainflow_tree/sql/mainflow_tree_area.sql:32`, `:42`, `:516` and `sql/qa.sql:314` —
  the SQL's own wording was left behind where the README was rewritten.
  - Lines 32 and `qa.sql:314`: a side channel carries "the polygons that are its own by their codes"; since
    this diff it is the polygons it lies in (README:67-68).
  - Lines 42 and 516: `below the tree` is "below the lowest tree segment of its stream". For 17 of the 20
    (337 ha; KUSR 15, TATR 2) a reattached tree segment has the polygon's exact pair; what they are below is
    the lowest main-flow segment, as README:72-74 and `qa.sql:213` now say.
  - **Rule:** code-check.md "A fix lands in one of two callers that share a harness"

## The questions

**1. `area_lift`.**

- Below its reach, onto another line: no. Of the 15,867 lifted `pair` polygons, 0 are on another blue line,
  0 at or below their reach top, 0 on another watershed code, 0 on a segment whose local code is not above
  the reach's, 0 on a segment whose own pair has a polygon, 0 off main flow.
- Past a segment that has a polygon of its own code: yes, 10 polygons (141 ha), see the fourth finding.
- 313 `pair` polygons have a main-flow segment of their range lying in them that is on their line but below
  their reach top (local codes out of order). The rule does not take those, which is right: they are
  downstream of the polygon already.
- A `range` placement for a polygon whose codes are on a main-flow segment: no. All 11 `range` polygons have
  `lower` as their code position, and a polygon whose pair is on a reach keeps `pair` in the `UPDATE`.
- Two lines: for `pair`, only the reach's own line is read (0 `pair` polygons have a hit on another line).
  For `range`, the lowest blue line key; unstated and unexercised (fourth finding).

**2. `area_side_hit` before `area_lift`.** A polygon can be both: exactly one is (9941495). The order
matches the README (rule 2 before rule 3). What the order costs there is the first finding.

**3. The weights in `qa_area.sql`.** I rebuilt the markers as temporary tables from the file's own
statements (40,729 markers) and measured:

- Exact: every weight is an integer, a whole multiple of its slot's base, with its number between 1 and
  2^40; every base is 2^(64(kind − 1)); no weight is NULL.
- Two markers with one weight: none in this build (40,729 distinct weights). The scheme does not guarantee
  it: the number is 40 bits of `md5(row number)`, and the first row number that repeats an earlier one is
  441,591, about ten times today's count.
- Overflow of a slot: no. It needs 2^24 (16.7 million) markers of one kind in one sum. Measured, the most
  markers of one kind upstream of one segment is 5,456 (`side channel`; then `other place` 1,331, `share`
  398, `side polygon` 278, `bad code` 254), and the most in one cumulative sum by codes is 9,548.
- The decode: `mod(div(x, base), 2^64)` returns the slot's sum, because every lower slot's sum is under its
  base and every higher one is a multiple of 2^64 times the base. `div` and `mod` on `numeric` are exact.
- The same weights on both sides: yes. `qa_marker_code` is built from `qa_marker.weight` after the `UPDATE`,
  and a marker is in one segment's code sum at most once (once as its own stream, or once per ancestor).
- One overstatement, not a finding: the comment says two sums are equal "only when the two sets of that
  kind are the same". With random 40-bit numbers that is overwhelmingly likely, not certain. I did not
  recompute the classes from the marker sets themselves to check the decoded sums against them.

**4. The geometry test.**

- Its `WHERE` selects 17,703 polygons, which is exactly the set I found away from its code position
  (15,867 + 1,825 + 11). It is defined by codes (the segment's local code is above the polygon's), so it is
  the full set as long as "away" means "onto a higher local code".
- Restored defects, each in a transaction that was rolled back:

| defect | placement test | geometry test |
|---|---|---|
| none (as built) | `t` | `t` |
| `pair` polygon 7532340 moved up its line from 17042019 to 17042128, which does not touch it | `t` | `f` |
| polygon 7515230 (`lower`) put on side-channel segment 700724180 of its pair, which does not touch it, as `pair_side` | `t` | `f` |
| the same, method left `lower` | `f` | `t` |
| `pair` polygon 7533497 moved from the top to the bottom segment of its own reach, which does not touch it | `t` | `t` |

- The last row is the gap: a polygon moved between segments of its own code pair is outside the `WHERE` and
  passes both tests. Only the comparison with the lookup could show it. `findings.md` already records that
  which run of a pair is taken is held by the code alone, so I list it as known, not as a finding.

**5. Figures in README "Upstream area" against the database.** All of these agree: the six method rows and
their areas; 15,867 moved (3,547,842 ha); unassigned 53,208 / 60 / 20 with 838,859 / 3,623 / 351 ha; 27,097
outlets summing to 110,143,331 ha, equal to the area assigned; every segment positive; steps 4,483,174 /
93 / 4 (90 dead ends and 3 cut-offs by junction, 4 cut-offs by line); outlets 26,690 at BC's edge, 383 dead
ends, 23 with no parent, 1 cut-off; 179,631 ha above the 384, the largest 50,535; shares 1,899 segments,
181,108 ha, 1,116 polygons, median 13.7; 1,457 bad-code polygons (45,175 ha); Skeena 5,440,479, Nechako
4,725,749, Fraser 23,203,431 ha, apart from the polygons under their code by 0.0027%, 0.0010% and 0.0502%;
the side-channel readings (53,007 and 1,580; 228,962 to 229,063; 302,611 to 302,813; 87078680 at 302,611);
the comparison's five counts and every class count (217,655 rows). One disagrees: the polygon of the
largest share (third finding). The counts quoted from the build before the fix (6,368 of 23,897, 67 of 96,
5,470 of 8,431) agree with `findings.md`; they cannot be re-measured on this build.

## Not checked

- The repo's test suite as a whole (by instruction), and `mainflow_tree.sh`, the area build and the
  comparison were not run. Only the two placement tests were run, around the restored defects.
- Whether the line with more segments is the right line for the 2 pairs on two lines, and whether the
  lowest run is right for the 14 pairs with several (accepted as exercised by few polygons).
- The comparison's classes against classes computed from marker sets.
- The KLUM and SSNbler figures (pending, by the brief).
- `code-check-r.md`, `code-check-shell.md` and `code-check-spatial.md` beyond the sections named above.
