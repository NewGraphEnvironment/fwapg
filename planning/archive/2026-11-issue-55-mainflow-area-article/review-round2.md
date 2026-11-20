## Checklist read

- code-check-infra.md: in full (cloud-init, OpenTofu, DigitalOcean, Docker/Postgres, Tailscale/S3).
- code-check-python.md: in full.
- code-check.md: the prose of all 14 H3s under `## Mechanisms`, table rows skipped. No other headings read.
- code-check-spatial.md: "A Freshwater Atlas main stem's downstream end lies on the receiving river's centreline", "FWA `upstream_route_measure` misses the next segment's start", "sf: `st_intersection()` / `st_difference()` return a GEOMETRYCOLLECTION", "A coordinate stored as an attribute can disagree with the geometry", "`sf::st_read()` promotes a mixed POLYGON/MULTIPOLYGON layer", "A label slice that ends exactly on a grid edge drops that edge". 6 read; the rest not read.
- code-check-r.md: "Postgres row order is never fixed unless the query fixes it", "`ifelse()` with an all-NA test returns a logical vector", "`identical()` on two reader results tests the reader". 3 read; the rest not read.
- code-check-shell.md: "psql does not interpolate `:'var'` ... `\quit N` exits 0", "`sed 1d f1 f2 f3` strips only the FIRST file's header". 2 read; the rest not read.

## What was run

- A detached worktree of HEAD ee66abc (since removed). `article_render.sh` exited 0 and wrote 5.2 MB. I purled the Rmd and ran the setup, helpers and checks chunks in R to read every check value.
- Read-only SELECTs on the local DB, filtered by ids or by MORR. The provincial counts in SQL comments were not re-counted (out of the brief's filter rule).
- A sample of 56 confluence_share.csv rows (every 300th) re-run through the current `confluence_share.sql` (ordered sums) gave byte-identical fields to the committed CSV.

### The new case-3 claim, against the database: it holds

- Side channel 360226583 (all `reattached`). Segment 139049288 (localcode …816714, 3,409.5 m) has `ST_Relate(seg, 7662562) = F1FF0F212`. The segment's interior meets the polygon's boundary in a line and never its interior, so it is the polygon's edge for its whole length. Build test `ST_Intersects(w.geom, ST_LineInterpolatePoint(s.geom, 0.5))` = TRUE; distance to the boundary 4.10e-11 m.
- Segment 139047882 (localcode …816763, 112.8 m) against 7662598: `F1FF0F212` as well. Build test = FALSE; `ST_Distance` = 0.
- "Decided by floating point" needs 7662598 to be otherwise eligible for rule 3. It is. Its localcode …816763 is 139047882's (the pair), its method is `lower` (not pair/range), and the main flow inside it (139047826, 139048112) has wscodes …816714 and …816763. Those are other streams, so the rule's own-wscode main-flow exclusion does not fire. 7662562's only pair segment is 139049288. Both polygons and 9742603 measure on the same side of the merged side-channel line. 7662598's segment 139050123 is main flow of its own wscode, so "stayed with the river" holds.
- Floodplain shares are 0.97484 and 0.97527. Printed as "97% and 98%", which is true by rounding. Side lengths: 3,409 and 113 m.

### The case-3 checks test what they say

- `edge_m` reads 3,409.5 and 112.8 against `side_m` 3,409 and 113. Point touches by neighbouring segments add only 0.01 to 0.02 m.
- Mutation: shifting the side channels 0.5 m drops `edge_m` to 0.04 m, so the check fires. A 3 cm shift drops 7662562's figure to 238 m, which fires too.

## Findings

- **[severity: bug]** extras/mainflow_tree/article/mainflow_tree_area.Rmd:307: "The third polygon, no side channel near it, lies 5% in the floodplain …" is false against the database. 9742603 is **44.3 m** from segment 139049288, the case's own side channel (DB `ST_Distance`; the extract gives 44.2 m), and it shares boundaries with both of the other case polygons (distance 0). What the search established, and what the bullet on line 297 and the popup ("no side channel touches it") say, is that no side channel *touches* it. "Near" widens "does not intersect" into a proximity claim that the data contradicts.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (compression gains a quantifier; "treat any sentence that gained a quantifier … as unsupported until the source is checked").

- **[severity: fragile]** mainflow_tree_area.Rmd:130-134 (the `lies_in` comment). It says `lies_in` is "'lies in' as the build tests it: ST_Intersects with the midpoint … within 1 cm". Case 3 disproves the equivalence on exactly the case the comment names ("a midpoint can sit on a polygon's edge"). On the extracts, `lies_in(mid(139047882), 7662598)` is TRUE, while the build reads it as outside (`ST_Intersects` FALSE). `lies_in` is also TRUE for 139049288 in 7662562, so it cannot tell the two case-3 polygons apart. Its justification is also off by a factor of about 5: a 6-decimal lon/lat step is 0.11 m in latitude and 0.065 m in longitude at 54° N, so rounding moves a point by up to about 5 cm, not 1 cm. **No check passes that should fail today.** `lies_in` is used only in case 2, where the midpoint is 720 m from the edge. But the comment states a property that is false, and any later use on an edge midpoint would assert the build's opposite.
  - **Rule:** code-check.md "A guard that fails toward pass" ("A comment stating a property is an unexecuted claim … execute it over the population it quantifies over"), and "A proxy is not the property".

- **[severity: fragile]** mainflow_tree_area.Rmd:254 and extras/mainflow_tree/README.md:246-247. Round 1 narrowed the sentence, and it still says "every number on this page taken from the extracts is checked" (README: "checks every number it takes from them"). It then lists the database-only facts as "(that a polygon or a mouth lies outside BC, or on its edge)". Both halves miss members:
  - Extract numbers printed with no `need()`: `ha(f2$area_ha)` (case 2), `ha(src5d$area_ha)` and `nrow(sh5)` (case 5, "8 segments"), `ha(j6$upstream_area_ha)` and `ha(o6$upstream_area_ha)` (case 6). Also, nothing ties case 5's "nearest the median" share to the README's median of 14 ha.
  - Database-only facts outside the parenthetical: case 3's "inside by 4e-11 m" and "outside at a distance of 0", which carry the case's whole reading. The extracts cannot reproduce them: in the extracts both midpoints sit 1.7e-11 and 3.5e-11 m from the edge, `st_intersects` is FALSE for both and `lies_in` is TRUE for both. Also case 6's "1.6 km" and "within 42 m", case 7's measures 314/506/667 (the extract has no measures), and case 2's "three segments up its line".
  - I checked every one of these against the DB, this round or in round 1, and all hold. What is false is the page's account of which numbers are checked.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" ("Terminating means enumerating every claim").

- **[severity: fragile]** planning/active/findings.md:70: "MORR 7662562 (runs through), 7662598 (touches), 9742603 (not touching)". The first label is false against the database: 139049288 lies on 7662562's boundary (`F1FF0F212`) and does not run through it. The correction exists only in progress.md:21, and findings.md:24 still describes the case as "a polygon a side-channel segment runs through, one it only touches". A reader using findings.md as the research record gets the disproved premise. Add a dated correction under it.
  - **Rule:** none (planning.md, "findings.md": what has been learned; feature-workflow "Bodies drift at the moment work finishes").

## Mechanism

**A proxy standing in for the property, or a self-set label read back as if measured** (code-check.md "A proxy is not the property" and "Verification that reads its own output"). A number or claim is taken from an adjacent quantity: a closest approach for a mouth distance, a status flag for a geometric property, a label the extract SQL assigned itself, or a 1 cm distance for the build's `ST_Intersects`. Every place it reaches, with a measured verdict:

1. **Case 6 mouth distances** (Rmd:224-226, 349, 355; case6.sql header). `mouth()` takes the line's start vertex as its mouth, which stands in for "downstream end". It **holds**. 212039207: z 1028 at the start and 1077 at the end; no segment at the start, two at the end. 212039334: z 1040 at the start and 1083 at the end. 351.3 m and 165.7 m match the text (351, 166). The "42 m" (Rmd:355) and the "77 m" (case6.sql) are labelled as segment closest approaches and measure 41.98 and 76.66. **Holds.**
2. **Case 3 `kind` labels** (case3.sql VALUES; Rmd:170-171). The check "one polygon of each kind" reads back labels that case3.sql assigns. It cannot fail while the three ids lie inside a view built from them (vacuous, same shape as round 1's case 2 `moved`). For each label's property:
   - *not_touching* is tested for real (`side_m == 0`); it holds. The prose widens it to "no side channel near it", which is **false** (44 m; finding 1).
   - *midpoint_inside* is proxied by `method == "pair_side"`. The DB holds it (`ST_Intersects` TRUE, 4.1e-11 m).
   - *midpoint_outside* is proxied by `method == "lower"`, and `lower` alone does not imply "no midpoint in it", since the main-flow exclusion could have refused the polygon. Measured: the exclusion does not apply (only other wscodes' main flow is inside), the build test is FALSE and the distance is 0. **Holds**, but it rests on the database alone. The extracts cannot see it (finding 3).
3. **Case 3 "all of it on the polygon's edge"** (Rmd:182-192). Length within a 1 cm band, with ±50 m / ±5 m tolerances, stands in for the line lying on the boundary. **Holds**: DB `ST_Relate F1FF0F212` for both, and a 0.5 m shift makes the check fire. With ±50 m on each of `side_m` and `edge_m`, up to about 100 m off the edge could pass, which is loose against "whole 3.4 km" but not false.
4. **`lies_in` as the build's midpoint test** (Rmd:130-134). The proxy diverges on edge midpoints (finding 2). Its only use, case 2 (720 m margin), is unaffected.
5. **Case 2** (Rmd:153-166). The round-1 fix replaced the self-set `moved` flag with codes from the extract (`g2$localcode != f2$localcode`, same wscode) and geometry: midpoint 720.2 m from the edge, segment wholly inside. **Holds.** `moved` is still written by case2.sql:575 but no longer read.
6. **Case 4 "connector … 1 m outside"** (Rmd:203-204, 323). sf distance on the extract is 0.824 m (DB 0.83). "Connector" (edge type 6010) is from round 1's DB read and is not checked in the render. **Holds.**
7. **Case 7** (Rmd:229-240). Areas, the polygon pair and code order are all read from the extract. Ltree text comparison works because the labels are padded the same (…059087 < …077907). **Holds.**
8. **Chart 711** (Rmd:247). A count of NA, with `lookup_missing > 0` on each. A real check. **Holds.**
9. **confluence_share.sql "same digits"** (header). Ordered sums; a 56-row sample re-run is byte-identical to the committed CSV. **Holds.**
10. **"Every number … checked"** (Rmd:254, README:246). A narrowed quantifier that still over-reaches (finding 3).
11. **Case 3 "decided by floating point" / "the midpoint test splits them"** (Rmd:307, 309, 395; case3.sql header). The claim is that the margin alone decides. **Holds**: both polygons satisfy every other rule-3 condition (pair codes, method, main-flow exclusion), measured above.
