# Code-check round 3: #24 diversions (ce4add3...HEAD)

## Checklist read

- code-check-infra.md: in full.
- code-check-python.md: in full.
- code-check.md: "A proxy is not the property" and "A guard's scope, escape hatches, and remedies" in full, tables included. The prose of the other 12 H3s under `## Mechanisms`, `|` rows skipped. The 23 H3s outside Mechanisms I judged from the index.
- code-check-shell.md: 7 of 67 headings read: "psql does not interpolate `:'var'` inside a dollar-quoted string, and `\quit N` exits 0", "`mktemp` template needs enough X's", "A second `trap … EXIT` replaces the first", "Heredoc precedence in pipelines", "A heredoc whose body contains its own delimiter ends early", "Empty arrays under `set -u` on bash 3.2", "Quoting". I did not read the other 60.
- code-check-r.md: 2 of 111 headings read: "Postgres row order is never fixed unless the query fixes it", and "An `information_schema` lookup by the literal table name misses what Postgres resolves" (which holds the correlated-subquery paragraph). I did not read the other 109.
- code-check-spatial.md: 4 of 93 headings read: "FWA `upstream_route_measure` misses the next segment's start", "FWA main flow is not edge type 1000 alone", "A Freshwater Atlas main stem's downstream end lies on the receiving river's centreline", "A name is not a key". I did not read the other 89.

My only database query was one read-only SELECT on `whse_basemapping.fwa_stream_networks_sp`. I did not run the job, the tests, or any write.

## The mechanism

Round 2's two findings have one cause. A predicate or a sentence was checked against the Nechako case and nothing else. It was true there because of the case's sizes (a 14,000 km² diversion against small neighbours), its counts (479 of 483), or its geometry (a placed outlet on each route, no junction at the exit vertex). It was not true because of the property it stood for. Below are all the places in the diff this mechanism reaches.

## Findings

- **[severity: fragile]** extras/pcic_crosswalk/sql/qa.sql:321. In the area test, the position-parent conjunct `p.local_area_ha <= p.upstream_area_ha - t.upstream_area_ha + 0.01` is the same proxy round 2 removed from the flow-parent side.
  - On a correct build it always holds, because P's other children's areas are ≥ 0. So it refuses nothing it should accept.
  - The bad build it is there to catch: the flow parent R is right, but the diversion's area comes off no sub-basin. One example is 06's area CTE giving the diversion a NULL parent instead of `position_parent_subid`. Then P keeps the area, and `p.local = p.up − others`.
  - The conjunct reads `f` only if P's other FWA children together have less upstream area than the diversion. That holds for the Nechako (14,000 km² against the canyon's side creeks). It does not hold for a small diversion whose position parent has large tributaries.
  - On the Nechako, "Nechako Reservoir weights" (canyon share < 0.1) also catches this defect. No generic test does.
  - Fix: test P by its definition, the way R is now tested. Join `kids` a second time on `p.subid` and require `abs(p.local_area_ha - (p.upstream_area_ha - coalesce(kp.area, 0))) <= 0.01`. `kids` uses `coalesce(position, fwa)`, so `kp.area` includes the diversion's area, and the 06 defect above then fails whatever the diversion's size.

- **[severity: fragile]** extras/pcic_crosswalk/sql/pcic_crosswalk06_subbasins.sql:186-192 (guard 2, the `position_parent_subid = x.anchor_subid` arm). qa.sql:247 (`dv.position_parent_subid IS DISTINCT FROM x.fwa_parent_subid`) asserts the same thing. Both assume a listed diversion's FWA position parent P is never its PCIC ancestor R. On the Nechako that holds only because a placed outlet sits on each route: 1008709 on the spillway, and 1002307 in the canyon. (Even if 1002307 were unplaced, P would still not be R here, because R sits on the spillway, off the FWA route.)
  - What the README admits. README step 4 asks for a listing wherever PCIC's water leaves a lake by another route, so that the outlets above can place. That also covers a lake whose two routes rejoin before any placed outlet. Take PCIC's arm with no placed outlet: R is then the first placed outlet below the rejoin, which is also P.
  - What 06 does then. The listing is still needed for placement, which is the reason step 4 gives. But 06 stops the job: "have no placed outlet below their exit, or reach their PCIC ancestor on the FWA too: nothing to divert".
  - Why the stop matters. The refusal itself is correct as far as it goes: without it, 07 would add the diversion to R's own segment twice, once by the position join and once by the CASE. The problem is the message. "nothing to divert" reads as "delist it", and delisting brings back the broken chain the listing was added to fix. That is a guard firing correctly and pointing at the wrong fix.
  - The Nechako itself would reach this arm if 1008709 (the spillway gauge outlet) were unplaced and 1002307 were too. R would then be 1008709's anchor below the Cheslatta, and so would P.
  - Fix, one of two:
    - (a) Handle P = R as a placement-only listing. Leave `fwa_parent_subid` as 06 found it. Add the diversion in 07's CASE only where `d.area_parent_subid IS DISTINCT FROM d.fwa_parent_subid`. Relax qa.sql:247, and qa.sql:348's "exactly one segment", to match.
    - (b) Keep the refusal, but say what it found: the listed outlet reaches its PCIC ancestor on the FWA, so it can be placed but not diverted, and this case is not handled yet.

## Every place the mechanism reaches

"Generic" means the line must hold for any correctly listed diversion. "Deliberate" means a Nechako test or note that hard-codes ids or numbers on purpose.

| place | kind | Nechako-specific because | verdict |
|---|---|---|---|
| qa.sql:321, area test, P conjunct | QA predicate | the diversion's area dwarfs P's other children | **defect** (finding 1): a wrong build of a small diversion passes |
| qa.sql:318-320, area test, R conjunct | QA predicate | nothing: it is the definition, rewritten in round 2 | generic, holds |
| 06:186-192 guard 2 and qa.sql:247 | refusal and QA predicate | a placed outlet on each route, so P ≠ R | **defect** (finding 2): a listing step 4 calls for is refused, with a misleading remedy |
| 06:195-208 guard 3 (R is the highest placed outlet on its segment) | refusal | 1008709 sits alone on its segment | over-strict but loud. If another outlet y sat higher on R's segment, y would own it. The diversion's flow would still reach the segments below through R's `q_acc`, as any stacked outlet's does. Only qa.sql:348 would then read n = 0. Not worth blocking; I note it for whoever lists the next one |
| 03 exit = the lake's lowest segment start (always a vertex), with 06:94-95 exempting diversions from the junction move | placement | no line joins the Nechako at Knewstubb's exit vertex. I checked: 0 other blue lines touch the downstream end of 701799415, and 1 touches its upper end | loud. If a PCIC child's line joined at the exit vertex, 06/07's step > 0 rule would parent that child below the diversion, onto P. qa.sql:113 would then stop the job, and there is no data fix, because 06 never moves a diversion. Round 1 recorded the QA catch; what is new here is that the stop cannot be cleared. 03 could refuse this case up front with a message naming it |
| 03:164-194 refusals (lake outlet with a series; exit usable as in 02) | refusal | none | generic. `islake` is the design's scope (a lake's exit), not a Nechako fact. The exclusion list copies 02:55-60, which is one fact written twice, but it agrees today |
| 03:15 "every outlet above 1007550 with a candidate broke the chain (479; 4 have none)" | comment | a measured count | deliberate, historical |
| 04:24-27, 05:8-9, 06:18-20, 06:164-167, 07:35-39 comments | comment | none | generic, and they match the code |
| README:9-13 "no outlet above the lake's outlet can hold the chain" | README | holds for any off-route receiving outlet R | generic. But it admits the P = R case 06 refuses (finding 2) |
| README:20-21, 31-33, 43-45, table rows 54/64/65 | README | none | generic, and they match 06/07 |
| qa.sql:52-57 flow-drop note ("Kenney Dam is one more") | comment, and a rate test | each diversion adds about one dropping pair, against a 0.1% ceiling (about 89 pairs) | deliberate. The test stays generic while diversions are few |
| qa.sql:160-161 child-on-another-line exclusion | QA predicate | none | generic. The diversion's flow edge is tested by qa.sql:348 |
| qa.sql:241-251 "every diversion is placed …", apart from line 247 | QA predicate | none | generic: an independent walk over `pcic_outlets` |
| qa.sql:273 (90% of LEUT/UEUT/UNRS/LNRS), :300 (exit, spillway 5%, canyon < 1 m³/s), :333 (canyon share < 0.1), :369 (Eutsuk) | QA predicates | hard-coded ids, measures and thresholds | deliberate Nechako tests |
| qa.sql:348 "exactly one segment" | QA predicate | needs P ≠ R (guard 2) and R owning its segment (guard 3) | generic within what 06 admits |
| qa_report.sql:5, 15-17 (snap stats exclude diversions) | report | none | generic |
| qa_report.sql:19-25 note (1008709/1001496 on 0.8 km², 1002307 on 14,000 km², "flagged by design") | report note | Nechako numbers | deliberate. The block's columns are generic |
| research/pcic_routed_flow_periods.md:30, pcic_schema.sql:50 | docs | none | generic. pcic_schema.sql:74 still says "placed outlets directly above the sub-basin", which is not wrong enough to break any consumer |
| mutation_checks.sh, nechako_measure.sql | one-off evidence | Nechako groups and ids | deliberate |

## Checked and clean (this round)

- Correlated subqueries qualify every outer column: 07's CASE (`d.` against `s.subid`), 06 guard 3 (`y.subid != dv.subid`), qa.sql:241's recursive CTE (`o.subid = x.subid`), 04 and 05's `NOT EXISTS`.
- No `:var` sits inside a `$$` body. Every check that must stop the job either `RAISE`s or is a qa.sql row that the `|t$` gate reads.
- Each new `LEFT JOIN fwapg.pcic_diversions` is on its primary key, so none fans out. 04's `UNION ALL` branches give the same columns in the same order.
- Row order: 03's `ORDER BY downstream_route_measure LIMIT 1` is unique on a blue line, and 07's `array_agg(d.subid ORDER BY d.subid)` is ordered.
- Topology where R lies downstream of P on the FWA path: the R conjunct of the area test, 07's FILTER/CASE, and the "exactly one segment" test all hold there. No double count.
- Readers of `fwapg.pcic_diversions` all run before pcic_crosswalk.sh renames it. days_build.sh and pcic_test.sh run only 06_daily, which does not read it.

## Clean otherwise

Beyond the two findings, I found nothing that fails, leaks, or loses data.
