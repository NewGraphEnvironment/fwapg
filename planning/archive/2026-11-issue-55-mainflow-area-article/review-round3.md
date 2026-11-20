## Checklist read

- code-check.md: "A proxy is not the property" and "A guard's scope, escape hatches, and remedies", both in full (prose and table rows).
- Other headings were not read this round. My findings rest only on those two.

## What was run

- A detached worktree of HEAD 668db13, since removed. `article_render.sh` exited 0 and wrote 5.2 MB. I pulled the rendered prose out of the HTML and walked it sentence by sentence (the enumeration below).
- R on the extracts: the case 1 downstream walk, case 2's line walk, case 3's side-channel set, case 5's shares, case 6's distances and dead ends, case 7's codes and areas.
- Read-only SELECTs on the local DB, filtered by ids or by the MORR group:
  - case 3: codes, sides and the nearest side channel;
  - case 4: area inside fwa_bcboundary;
  - case 6: `mainflow_tree_qa` rows and watershed keys;
  - case 7: `mainflow_tree_area_qa` classes and measures;
  - case 2: segment measures on blue line 360776359;
  - MORR: how many side-channel segments have their midpoint on a polygon's edge.

### Review of round 2's fixes

- The case 3 "nearest is 44 m away" sentence and its check hold. In the DB, the nearest segment to 9742603 with `blue_line_key <> watershed_key`, tree or not, is 139049288 at 44.27 m. No dropped side channel is closer: the three non-tree segments in the extract are farther away. The new distance check also closes a gap: `side_m == 0` alone could not tell a point touch from no touch.
- The `lies_in` comment now says "5 cm", which is the right order. The exact worst case at 54° N is 5.6 cm in latitude and 6.4 cm combined, which is still "about". It is used only in case 2, so not a finding.
- Case 2 area check (363.06 ha against 363), case 5 `nrow(sh5) == 8`, case 6 9 ha / 338 ha: all pass, and each pins the number printed.
- The "How to read a map" list and the README Article sentence are narrower than before. They still over-claim (finding 1).
- findings.md:70 is fixed. Line 24 is not (finding 3).

## Findings

- **[severity: fragile]** extras/mainflow_tree/article/mainflow_tree_area.Rmd:258 ("the numbers each case and the chart take from the extracts are checked … Some facts are from the database …, since the extracts cannot show them: …"). Also the `checks` chunk header at Rmd:123 ("Every number the article takes from the extracts") and extras/mainflow_tree/README.md:246-248 ("checks the numbers it takes from them"). Round 2's fix narrowed these sentences, and they still name members that are not checked. All the facts below hold against the extracts or the DB. What is false is the page's account of them.
  - **Extract numbers no `need()` pins:**
    - case 1, "with the lookup's areas it would take half". `share_lookup` for 123043588 is 0.5 in confluence_share.csv; it is never read.
    - case 5, polygon 8442664's "155 ha" (`ha(src5d$area_ha)`). Round 2 listed this one, and the fix added checks for its siblings but not for it.
    - case 5, "nearest the median". Nothing ties 13.7 ha to the median (case5.sql: 13.69; README: 14).
    - case 7, the literals "0.214", "1.418" and "1.632". Only their sum is pinned (equal to lookup minus tree, within 1e-6). Each end is pinned to ±0.1, so 1.632 is held only to [1.53, 1.73].
  - **Two members of the database-only list are given a false reason, "the extracts cannot show them":**
    - case 2's "three segments crossed": the streams extract's `downstream_id` chain from 123029079 passes 123029214, 123029265 and 123029504 (localcode …250158) before it reaches the polygon's …198620.
    - case 6's "42 m": `st_distance` of 212039207 and 212039249 in the extract is 41.98 m.

    Both could be checked at render time, and neither is.
  - **Facts from the DB outside the list** (all verified true): case 3, 9742603's "codes on side-channel segments only" and "on the same side of the same side channel"; case 6, "TUTR" and "reached by a fallback junction" (`junction_method = side_fallback`); case 7, "TUTR", and the classes "local codes out of order" for 212038785 and none for 212038783.
  - Either check the extract members (four `need()` lines, plus the two that are wrongly listed) and widen the list, or say "most numbers".
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" ("Terminating means enumerating every claim … and executing each"; a narrowed quantifier that still over-reaches).

- **[severity: bug]** mainflow_tree_area.Rmd:282: "it went to segment 123029079, three segments up its line". The polygon goes first to the top of its own reach, 123029539 (localcode …198620, measure 1090.6). The segments above it on blue line 360776359 are 123029504 (1108.8), 123029265 (1296.3), 123029214 (1652.8) and 123029079 (1994.0).
  - So 123029079 is the **fourth** segment up. Three lie between, which is what case2.sql's ORDER BY counts ("segments crossed") and what the "How to read a map" list says ("three segments crossed").
  - Read as written, "N segments up its line" puts the landed segment Nth, which is off by one. "Crossed" became "up" when the SQL's count went into the prose. "past three segments of its line", or "four segments up", is true.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" ("Compression runs both ways": a restatement that changes what the count counts).

- **[severity: fragile]** planning/active/findings.md:24: "a polygon a side-channel segment runs through, one it only touches, one it does not touch". Round 2 named this line beside line 70, and the fix corrected only line 70. 139049288 lies on 7662562's boundary (`ST_Relate F1FF0F212`, round 2) and does not run through it, so the research record still states the disproved premise.
  - **Rule:** none (planning.md, findings.md as what has been learned).

## Enumeration

Every numeric or factual claim in the rendered prose, the chart caption and the README Article section. C = checked (the `checks` chunk, check named by its message); L = listed as database-only in "How to read a map"; R = quoted from README (and matches it) or from a repo file; U = uncovered, with how I verified it.

**Intro / How to read**
- "seven of them on a map, one case each": U, structure (7 sections). True.
- "extracts of the 2026-11 build": U at render. article_extract.sh's build guard (1,898 share rows, 123039830 = 53,007) asserts it at extract time. True.
- "the numbers each case and the chart take from the extracts are checked": **false** (finding 1).
- "The province-wide counts are the README's": R; every one matches (below).

**Case 1**
- 360216952 (LSKE) a README test side channel: R (README "test side channels"); LSKE is U (DB group = LSKE). True.
- Exchamsiks River (360884603) enters it: U (extract: 123039760 gnis Exchamsiks, `downstream_id` 123039830 on 360216952). True.
- On through second side channel 360216962 to the Skeena: U (extract walk 123041439 → 123041497…123043588 on 360216962 → 123043992 main flow, 5.1 M ha). True.
- 5.06 to 5.11 million ha in the lookup: C ("case 1: the lookup gives 360216952 within the README's 4.26 to 5.11 million ha"; values 5,059,365 to 5,111,821).
- (the README: 4.26 to 5.11 million): R.
- 1,580 ha above: C ("123039759 and 123039469 read 1,580 ha"). 53,007 below: C. Mouth segment 51,420: C. 53,058 at its foot: C ("the bottom two segments read 53,058 ha").
- a 52 ha stream (360681805) has joined: C (51.8 and `downstream_id` 123040995). The id is U (extract `blue_line_key` 360681805). True.
- 123043588 takes 1.0%: C (0.0104).
- "with the lookup's areas it would take half": **U** (extract `share_lookup` 0.5). True, but unchecked (finding 1).
- On the ground, "north side of the valley, apart from the Skeena": a reading of the imagery, not checkable. "the lookup's 5 million ha": C, loosely (bound ≥ 4.26 M; values 5.06 to 5.11).

**Case 2**
- 15,867 (3,547,842 ha): R.
- 7745172 (LSKE, 363 ha): C (area, round 2 fix). LSKE is U (extract group). True.
- The one in LSKE or KLUM, 50 to 500 ha, that crossed the most segments: U, by construction of case2.sql's pick (filters and ORDER BY match the words). Not re-run (provincial).
- localcode 400.131612.198620 and segment 123029079: inline from the extract.
- "three segments up its line": L as "three segments crossed", with a false "cannot show" reason (finding 1). The wording is off by one (finding 2).
- On the ground, "lies wholly inside it, its midpoint 720 m from the polygon's edge": C.

**Case 3**
- pair_side 1,820 polygons, 95,860 ha: R.
- Three neighbouring polygons in MORR: MORR U (extract group). "Neighbouring": U (round 2, DB distance 0 between all three). True.
- First of the groups with mapped floodplain to hold all three kinds together: U (case3_search.sql ORDER BY array_position(MORR, …) first). True.
- Bullets:
  - ids, rules and given_to are inline. Methods: C ("is `pair_side`", "`lower`" ×2).
  - "a midpoint in it": L (4e-11 m).
  - "touches … no midpoint": C (edge_m 113) + L (0 m).
  - "codes on side-channel segments only": **U** (DB: localcode …815232 on 139048888 only, reattached). True; DB-only, unlisted.
  - "no side channel touches": C (44.3 m distance check).
- ff04 functional floodplain from stac-floodplains-bc: U (article_extract.sh: item morr_all_ff04). True.
- On the ground:
  - edge of both for its whole 3.4 km / 113 m: C (edge_m and side_m checks). Segment ids 139049288 and 139047882: U (extract localcodes …816714 and …816763 on 360226583). True.
  - 4e-11 m inside, 0 outside: L.
  - 97% and 98%: C.
  - "same side of the same side channel": **U** (DB, sign of cross product against merged 360226583 is −1 for all three). True; unlisted.
  - "one went to the side channel and one stayed with the river": C (pair_side / lower; rule 4 gives main flow; DB: 139050123 is main flow).
  - "nearest is 44 m away": C. "5% in the floodplain": C. "on the slope beside it": a reading of the imagery.
- Left for #53, "a side-channel segment often lies on a polygon's boundary": U. Measured in MORR: 115 of 379 tree side-channel segments (30%) have their midpoint within 1 cm of a polygon edge. "Often" holds there, and the closing section says the province is not measured.

**Case 4**
- 1000002557 (BEAV): id C; BEAV U (extract group).
- 766,913 ha: C (±1,000).
- "most of it across the border": U (DB: 7e-7 ha inside fwa_bcboundary). True, and an understatement of the "wholly" below.
- Two main lines 359572098 and 359024601; overrides.csv keeps 359572098: R (overrides.csv note); 359572098 C.
- Codes-only version moved it to the wrong line: R (README "three cross-border polygons of 63,000 to 767,000 ha").
- Rule 4 (lower), segment 868144442: C / inline.
- "a connector": U (extract `edge_type` 6010). True, unchecked.
- Rule 4's definition: R (README rule 4).
- On the ground:
  - "wholly in the Yukon": L.
  - "drains south across 60° N": U (extract: the connector's measure-0 vertex is at 59.99996 N, the other end north of 60). True.
  - "connector at the border": U (same). True.
  - "1 m outside": C.

**Case 5**
- 1,898, 181,075 ha, median 14 ha: R.
- 180011290 (SHEK): inline. "nearest the median": **U**. case5.sql picks by it; findings.md gives 13.695 against a median of 13.692. Not re-run (provincial); unchecked (finding 1).
- 13.7 ha: C ("the segment's share is its shares row").
- 8442664 "(155 ha)": **U** (extract 155). True, unchecked (finding 1).
- 8 segments: C. 70.0 ha: C (sum = shared_ha). Keeps the rest on 180011831: inline.

**Case 6**
- 473 / 90 / 383: R.
- "Two in TUTR": **U** (DB group TUTR for both). True; unlisted.
- Mouths 166 m apart: C. 9 ha / 338 ha: C.
- "carried to segment 212039249": inline `downstream_id`; C (`t6x` exists).
- "212039334 … is an outlet": U. The extract has `downstream_method` NA. The check `any(dead_end & is.na(method))` is also met by 212039158, a second dead-end outlet in the extract, so it does not pin this segment. True.
- On the ground:
  - "a side channel reached by a fallback junction": **U** (DB: `blue_line_key` 360230419 ≠ `watershed_key` 360863432; `junction_method` side_fallback). True; unlisted.
  - mouth 351 m: C.
  - 42 m further up: L, but computable from the extract (41.98; finding 1).
  - "ends on the Alaska border": L ("mouth on BC's edge"); it is at 59.61 N, -135.10, where the neighbour is Alaska.
  - code junction on 360864386, 1.6 km: L (DB `junction_gap_m` 1586).

**Case 7**
- 212038783 (TUTR), "the one main-flow segment … nothing routed differently … nothing odd in its codes": R (README "1 not explained"); TUTR U (DB). True.
- 863.6 / 865.3: C.
- Black-outlined polygon is the lookup's: U (case7.sql focus = lut; DB lut row → 8628560). True.
- Blue line 360860536: U (extract). Code …077907 on two reaches, lower …059087 between: C ("share a local code, with a lower one between them"). The literal digits are U (extract). True.
- Measures 314 / 667 / 506: L (DB 314, 667, 506).
- Polygons 8628560 / 8632200 to 212038745: C. "0.214", "1.418", "1.632": **U**, only the sum is pinned (finding 1). Extract values 0.214064, 1.418177 and 1.632241. True.
- qa_area.sql class "local codes out of order" for 212038785, none for 212038783: **U** (DB `mainflow_tree_area_qa`). True; unlisted.

**Chart**
- 16,745: C + R. Median 0.5%: C + R. 15,864: C + R.
- 16,034: inline (16,745 − 711, both checked).
- 50%: C + R.
- Caption "711 places": C. Colours blue for tree, orange for lookup: match the code.

**Closing section**
- 4e-11 / distance 0: L. "Both almost wholly in the floodplain": C. "Same side": U, true.
- "How often … is not measured here": true (no province-wide figure on the page). Judgements on cases 6 and 7: not checkable.

**README Article section**
- Seven cases, named: match the page's seven headings.
- Renders with no database: true (the render ran with DATABASE_URL and PGSERVER unset).
- "checks the numbers it takes from them": false as stated (finding 1).
- gq#123, and the render script says how to install: true (article_render.sh REFUSE message with the pin).

**New or edited SQL comments**
- case2.sql "15,848 … with the 19 … 15,867": consistent with README ("19 go up their line by rule 1").
- case3.sql 3,409 m / 113 m / 4e-11 / 0 and the search order: true.
- case4.sql 766,913: true.
- case5.sql 13.69: consistent with findings.md (13.692).
- case6.sql 77 m / 166 m: true (76.66 / 165.7).
- case7.sql "the one": R.
- confluence_share.sql "same digits": round 2's re-run.

**Complete?** Yes. Every numeric or factual sentence in the rendered prose, caption and README Article section is listed above. None is false against the extracts or the database, except case 2's off-by-one wording (finding 2). The uncovered members that the page's account mislabels are gathered in finding 1. Not re-derived, because the brief limits queries to ids or a group: the provincial counts in SQL comments and README quotes (taken from the README as written), case 2's "most segments" and case 5's "nearest the median", both of which are the SQL picks by construction.
