# Findings — Upstream area on the main-flow tree, so SSN additive functions need no hand overrides (#4)

## Issue context

**If we do it:** every segment of the main-flow tree (#2) carries the area that drains through it along the tree, so an SSN additive function (SSNbler `afv_edges(infl_col = ...)`) or any area weighting can be built for any watershed group with a join and no hand overrides. **If we never do:** the network is automatic but its weights are not: each project re-derives area per edge, and overrides side channels by hand wherever the tree reattached one (19,745 side channels province-wide).

## Problem

An SSN model built on the tree needs one area per edge: the land draining through the edge's downstream end. SSNbler turns these into segment proportional influences at each confluence (area of the edge / sum of areas of the edges meeting there), so they must be additive along the tree. Neither source FWA offers gives that on the tree.

**1. `FWA_WatershedAtMeasure()` on secondary-flow segments** (edge type 1350, all with `watershed_key` 360887278, the Skeena) returns three different kinds of answer (measured when this issue was filed; re-measure in Phase 1):

| blue_line_key | measure | edge_type | polygons | km² |
|---|---|---|---|---|
| 360216952 | 1100 | 1350 | 1 | 50,609 |
| 360216952 | 1800, 2000, 2400, 2700, 3000 | 1350 | **0** | — |
| 360216952 | 3300 | 1450 | **0** | — |
| 360222215 | 60 | 1350 | 1 | 45,681 |
| 360237491 | 150 | 1350 | 1 | 45,581 |
| 360222216 | 1400 | 1350 | 1 | 19 |

Empty on most of side channel 360216952, the whole parent river on others (double counts at a braid), a local area on one. It is also one call per edge, slow at the scale of a watershed group. Related upstream: `smnorris/fwapg#37` (fails at measure 0), and #49 (two unguarded scalar subqueries in the same function).

**2. The lookup (`fwa_streams_watersheds_lut` joined to `fwa_watersheds_upstream_area`)** matches each segment to one fundamental watershed by its watershed codes (`wscode_ltree`, `localcode_ltree` and group, nearest centroid when several match), falling back to the polygon at the segment's midpoint only when no code matches; `fwa_watersheds_upstream_area` holds that polygon's upstream area (every polygon `FWA_Upstream` puts above it). Measured on the 2026-10 tree (4,510,368 segments), 2026-11-19:

- **Side channels get their river's area.** A side channel carries its river's watershed codes, so the code match gives it one of the river's polygons. Every reattached segment of the four Skeena test side channels gets 4.2-5.1 million ha (the Skeena), where the water actually in them is one tributary's:

  | side channel | lookup area (ha) | tributary entering it | its area (ha) |
  |---|---|---|---|
  | 360216952 | 5,059,365-5,111,821 | 360884603 | 51,420 |
  | 360222215, 360222216 | 4,568,001-4,797,374 | 360883243 | 228,943 |
  | 360237491 | 4,255,363-4,558,110 | 360881231 | 302,611 (first segment above its mouth) |

- **Mouth segments can get their parent's area.** 8,111 tree segments are matched to a polygon whose watershed code is another stream's (the midpoint fallback) (7,592 main flow, 270 of them 1450 connectors; 515 reattached; 4 followed). Example: 360881231's mouth connector (`linear_feature_id` 87078680) is matched to a Skeena polygon and gets 4,558,110 ha; the next segment up gets 302,611.
- **2,941 tree segments have no lookup row** (2,353 main flow, 584 reattached, 4 followed), so a left join gives them NULL and fwapg's own `fwa_streams`, which inner-joins the area table, leaves them out (#33).

One stream-temperature project's SSNbler script hit all three: it overrode eight side-channel edges (two on each test side channel) with the area of the tributary entering them, moved one edge's point to measure 10 because the function failed lower down, and sampled each edge 10% above its bottom so two edges meeting at a confluence would not get the same area.

## What to build

A per-segment upstream area on the tree, built by `extras/mainflow_tree` and stored with it: the area of land whose water passes the segment's downstream end, routed along the tree.

Two ways to compute it (a choice for the plan gate):

- **A. Accumulate over the tree.** Assign each fundamental watershed polygon (`fwa_watersheds_poly`) to exactly one tree segment, then sum the polygons' own areas downstream through the tree. Additive at every confluence by construction (area below = sum of areas above + the local polygon), which is what SSNbler's proportional influences assume. Needs a rule for polygons that hold several segments, river polygons that hold side channels, and segments with no polygon. Leaning this way.
- **B. Lookup area, patched.** Keep the lookup's area on main flow, and give each reattached segment the sum of the mouth areas of the lines entering its side channel at or above it (recursively for nested side channels). Reproduces the hand overrides and reuses numbers that match bcfishpass. It is not additive at a side channel's mouth: the river segment just above it already counts the tributary (its code puts it under the river), so that confluence counts it twice. The mouth segments in a parent's polygon still need their own fix.

Decisions for the plan gate:

- A or B.
- Where it is stored: a column on `whse_basemapping.fwa_stream_networks_mainflow_tree` (`upstream_area_ha`), or a separate table keyed on `linear_feature_id`.
- Units and precision (ha like the lookup, or m² as SSNbler projects have used).
- What happens to `FWA_WatershedAtMeasure()`'s empty answer on side channels: fixed here, filed separately, or left (the tree area does not need it). Phase 1 checks whether it is #49's defect.

## Done when

- Every tree segment has a non-null, positive area.
- **Additive:** at every tree node, the area of the segment below is at least the sum of the areas of the tree segments above it (equal within the local polygon's area under A). Downstream along each line, area never decreases.
- **Skeena test side channels:** the reattached parts of 360216952, 360222215, 360222216 and 360237491 get the area of the tributaries entering them (table above, plus local area), not the Skeena's.
- **Main flow agrees with the lookup** wherever the segment's polygon is its own and no reattached side channel lies above it; every other difference is attributed to a class by a query.
- **SSNbler end to end:** on a group holding the test side channels (KLUM) and on the whole Skeena, `lines_to_lsn` then `afv_edges(infl_col = <the area>)` and `afv_sites` run with no zero or missing area warnings and no overrides; additive function values lie in (0, 1] and equal 1 at the outlet. Ideally `ssnbler_check.R` gains this as an optional step.
- QA tests in `extras/mainflow_tree/sql/qa.sql` for the additivity and the test side channels; `README.md` and `research/fwa_mainflow_tree.md` ("Not settled") updated.
- Runs inside `mainflow_tree.sh` in minutes, not hours.

## Not in scope

- Merging segments between confluences into longer SSN edges (a modelling choice; SSNbler accepts the segments as they are).
- Covariates (air temperature and the like).
- Filling the lookup itself (#33), unless option B needs it.

## What it needs

A database with the FWA, the blue line paths and the main-flow tree loaded (`extras/mainflow_tree/mainflow_tree.sh`), and SSNbler from the fork (`pak::pak("NewGraphEnvironment/SSNbler@37ca338")`) for the end-to-end check. Memory limits for SSNbler are in `extras/mainflow_tree/README.md` ("SSNbler check"); run one at a time.

Follows #2. Related: #19 (SSNbler on every watershed group), #33 (lookup gaps), #34 (downstream walks over the tree).



## Plan-time measurements (2026-11-20, read-only, local provincial database, PostgreSQL 17.5)

Tree: 4,510,368 segments (4,451,744 main flow, 58,447 reattached, 177 followed). `fwa_watersheds_poly`
about 3.25 million polygons; `fwa_watersheds_upstream_area` has `watershed_feature_id integer,
upstream_area_ha double precision`. `fwapg.downstream_ids` (the #34 benchmark table) is not in the
database; `fwapg.blk_parents`, `fwapg.blk_paths` and `fwapg.mainflow_tree_qa` (504 rows) are.

Polygons by whether a tree segment shares their codes (`wscode_ltree`, `localcode_ltree`):

| class | polygons | area (ha) |
|---|---|---|
| codes on a main-flow tree segment | 3,180,734 | 93,501,694 |
| watershed code not in the tree | 53,225 | 841,820 |
| codes on a reattached or followed segment only | 8,449 | 407,571 |
| watershed code in the tree, local code not | 2,985 | 54,929 |
| under `999` | 60 | 3,623 |

Tree streams with no polygon at or under their watershed code (a proxy for "no area above"): 129
main-flow segments on 84 streams, 92 km; 128 of them have a lookup row.

The four test side channels through the lookup (tree segments only): every one reads its river's area,
with a polygon of 2 to 303 ha that carries the Skeena's watershed code (`400`), which the side channel
carries too.

| side channel | tree segments (measure) | lookup polygon(s), ha | lookup area (ha) |
|---|---|---|---|
| 360216952 | 0 to 1676.5 (7 segments; 1699.6 and above are not in the tree) | 2.0, 7.4, 8.9 | 5,059,365 to 5,111,821 |
| 360222215 | 0 to 194.0 (3; 297.7 and above not in the tree) | 19.3 | 4,568,001 |
| 360222216 | 0 to 962.1 (4; 1386.5 and above not in the tree) | 64.6, 19.3 | 4,568,001 to 4,797,374 |
| 360237491 | 0 to 191.8 (3; 325.3 and above not in the tree) | 27.5, 303.2 | 4,255,363 to 4,558,110 |

The tributaries at their mouths: 360884603 51,420 ha; 360883243 228,943 ha; 360881231 4,558,110 ha on
its mouth segment (87078680, matched to a Skeena polygon) and 302,611 ha on the next segment up
(245024871, measure 392.6).

## What the code already has (read at plan time)

- **The export is not a committed file.** `extras/mainflow_tree/fwa_stream_networks_mainflow_tree.csv.gz`
  is ignored (`.gitignore`, `*.gz`) and so is `extras/mainflow_tree/data/`. `load.sh` does not load the
  tree. The export is `SELECT *` of the tree table, so a new column changes the file's shape and no loader.
- **`sql/qa.sql`'s contract.** `mainflow_tree.sh` fails unless every test line ends `|t`; a NULL result
  (a test over no rows) prints `name|` and fails too.
- **The tree's outlets.** 8 cut-offs, 473 dead ends and 23 `no_parent` mouths inside BC, plus 26,690
  mouths at BC's edge. The Nechako has 8 outlets, the Skeena 1.
- **A downstream pointer has a worked form.** Rule 1 ("node") of
  `planning/archive/2026-10-issue-34-measure-downstream-queries/scripts/sql/01_downstream_ids.sql`: the
  tree segment whose upstream end is this segment's downstream end, nodes at 1 cm, unique because the
  tree has no splits (asserted by `PRIMARY KEY (up_x, up_y)`). Its rule 3 ("junction") crosses gaps
  through the blue line paths. The whole table took 142 s and 385 MB province-wide there; no shipped job
  builds it.
- **An accumulation has a worked form.** `extras/pcic_crosswalk/sql/pcic_crosswalk06_subbasins.sql`
  gives each node a depth from the roots and refuses a tree with an unreached node;
  `pcic_crosswalk06_daily.sql` sums from the deepest level up, one level a statement.
- **The lookup's convention.** `load/fwa_streams_watersheds_lut.sql` matches a segment to a polygon by
  codes and group, nearest centroid when several match, then by the polygon at the segment's midpoint.
  `extras/lookups/sql/fwa_watersheds_upstream_area.sql` sums every polygon `FWA_Upstream` puts above a
  polygon, the polygon included (area at the polygon's outlet).
- **The SSNbler check.** `ssnbler_check.sh` exports `linear_feature_id, geom` only, and
  `ssnbler_check.R` stops after `lines_to_lsn`. The installed SSNbler where this runs is 1.1.2 with no
  GitHub remote recorded, so the pinned fork is installed before Phase 5.
  `afv_edges(edges, lsn_path, infl_col, segpi_col, afv_col, save_local, overwrite)`,
  `sites_to_lsn(sites, edges, snap_tolerance, save_local, lsn_path, file_name, overwrite, verbose)`,
  `afv_sites(sites, edges, afv_col, save_local, lsn_path, overwrite)`.
- **#49 is likely another defect.** Its two unguarded scalar subqueries raise `more than one row returned
  by a subquery used as an expression` (291 of 293 failures at measure 0); this issue's symptom is an
  empty result. Not measured yet.
- **Recorded runtimes disagree.** The #2 archive README: paths 35 min, tree 1 min, topology QA about
  35 min. `extras/mainflow_tree/README.md` (2026-10-10): 20 min in all (paths 16, tree 3, QA 1.5). #34
  measured the paths at 992 s. "Minutes" is judged against the README's figures.

## Phase 1 (2026-11-20): `FWA_WatershedAtMeasure()` on the test side channels

`scripts/01_watershedatmeasure.sql`. The same as the issue's table:

| blue_line_key | measure | edge_type | rows | km² | refine_method |
|---|---|---|---|---|---|
| 360216952 | 1100 | 1350 | 1 | 50,608.7 | CUT |
| 360216952 | 1800, 2000, 2400, 2700, 3000 | 1350 | 0 | | |
| 360216952 | 3300 | 1450 | 0 | | |
| 360222215 | 60 | 1350 | 1 | 45,680.7 | CUT |
| 360237491 | 150 | 1350 | 1 | 45,580.9 | CUT |
| 360222216 | 1400 | 1350 | 1 | 19.2 | CUT |

**Why it is empty** (`scripts/02_watershedatmeasure_trace.sql`, which counts the function's own CTEs at a
point). The empty points are on segments with a watershed code (`400`) and no local code: the seven
segments of 360216952 from measure 1699.6 up. The function finds everything upstream with
`FWA_Upstream(a.wscode_ltree, a.localcode_ltree, ...)`, which is NULL when the local code is NULL
(checked: `FWA_Upstream('400', NULL, '400.5', '400.5')` is NULL), so no basin, group or polygon is
collected. `ref_point`, the polygons within 5 m and the covered segments are all found (7 segments
covered at 1800), so `refine_method` is `CUT`, and the result is only what
`FWA_SliceWatershedAtPoint()` returns: 19.2 km² at 360222216 measure 1400 (also no local code), nothing
at 360216952 measure 1800 to 3300, where the slice is empty. So the 19 km² "local area" in the issue is
the same path as the empty answers, not a third kind.

It is not #49's defect: that one raises `more than one row returned by a subquery used as an
expression`; this returns quietly. Filed as #52.

158,188 network segments have a watershed code (not under `999`) and no local code: 110 main-flow tree
segments (all edge type 6010) and 158,078 outside the tree. No reattached or followed segment has a NULL
local code, so the kept part of a side channel always carries one.

## Phase 1: tree segments by what the lookup gives them

`scripts/03_lookup_classes.sql`, query A. "Another stream's polygon" sums to the issue's 8,111 and "no
lookup row" to its 2,941.

| source | own codes | own watershed code, another local code | another stream's polygon | no lookup row |
|---|---|---|---|---|
| mainflow | 4,387,951 | 53,848 | 7,592 (270 are 1450) | 2,353 (110 with no local code) |
| reattached | 39,867 | 17,481 | 515 (513 are 1450) | 584 |
| followed | 96 | 73 | 4 | 4 |

A class the issue does not name: 71,402 tree segments are matched to a polygon on their own watershed
code at another local code (the midpoint fallback, where no polygon carries the segment's code pair).

Tree segments with no lookup row, by edge type: 1250, 1,414; 1200, 667; 1450, 564; 6010, 150 (110 with
no local code); 1350, 87; 1300, 47; 1475, 12.

## Phase 1: polygons whose watershed code is on no tree segment

`scripts/03_lookup_classes.sql`, query C (query D was cancelled after 12 min; the prototype answers it).
None of the 53,225 has its watershed code on the network at all, and all are land polygons: 38,163
(373,186 ha) have a code more than one label deep, so an ancestor code can place them; 15,062
(468,634 ha) have a one-label code, with no ancestor to fall back to.

## Plan review (Plan agent, 2026-11-20; report in `review-4.md`)

Verdicts so far; the rest wait on the prototype (`scripts/04_prototype.sql`).

| finding | verdict | checked against |
|---|---|---|
| B1: decision 4 carries about 90 dead ends, not 473 + 8 | right | the #34 archive's `findings.md`: 383 of the 473 dead ends join a parent exactly at the parent's lowest segment start, as does every later line on their path, so the network ends there; 90 take a junction step onto the tree; the 8 cut-offs step to the next segment of their own side channel, off the tree. The count in the plan was mine and not measured. |
| G4, G7: the assignment rule's order, strictness and area source | right, adopted | `FWA_Upstream` in `db/schema.sql`; the prototype states the rule in its terms (own stream: the reach at the greatest local code at or below the polygon's; an ancestor: strictly below the branch's code) and sums `ST_Area(geom) / 10000` as the lookup does |
| A8: a test that returns no rows prints nothing and passes | right | `mainflow_tree.sh` checks that the output is not empty and that no line fails to end `|t`, so one test's missing line is not seen |
| G1: "own" must mean both codes | right | query A above: 71,402 tree segments on their own watershed code at another local code |

## Phase 1: the prototype (2026-11-20)

`scripts/04_prototype.sql` builds the whole thing province-wide in `fwapg.proto4_*`: 4 min 41 s
(segments and nodes 11 s, pointer 1 min 57 s, reaches 22 s, polygon assignment 1 min 40 s, depth and
local area 20 s, the level loop 7 s over 4,380 levels). No segment is unreached from an outlet, so the
pointer has no cycle. `scripts/05_prototype_measure.sql` and `06_zero_area.sql` measure it.

**Pointers.**

| method | segments | what they are in the topology QA |
|---|---|---|
| node | 4,483,174 | |
| junction | 93 | 90 dead ends, 3 cut-offs (path step 1 to 3) |
| line | 4 | cut-offs with a tree segment lower on their own blue line |
| none | 27,097 | 26,690 at BC's edge, 383 dead ends, 23 `no_parent`, 1 cut-off |

Outlets by kind and the area they drain: BC's edge 109,951,993 ha (largest the Fraser, 23,198,766);
dead ends 184,525 ha (largest 50,535); `no_parent` 5,360 ha; the cut-off 217 ha. Under the Fraser's code
4 dead ends (10,999 ha) and 4 `no_parent` mouths (891 ha) do not reach its mouth.

**Polygons by how the first rule placed them** (the rule before decision 6 was restated: the top segment
of the reach at the greatest local code at or below the polygon's, else an ancestor).

| class | polygons | ha |
|---|---|---|
| same code pair, main flow | 3,180,734 | 93,710,554 |
| same code pair, reattached | 8,444 | 407,541 |
| same code pair, followed | 5 | 30 |
| own stream, a lower local code (main flow) | 1,727 | 15,828,439 |
| own stream, a lower local code (reattached) | 56 | 158,932 |
| an ancestor code, one level up | 1,195 | 35,759 |
| an ancestor code, two or more levels up | 12 | 840 |
| unassigned: no ancestor in the tree | 38,158 | 373,892 |
| unassigned: one-label code | 15,062 | 465,886 |
| under `999` | 60 | 3,623 |

Areas here are `ST_Area(geom) / 10000`, which differ a little from the `area_ha` attribute used in the
plan-time table above. The outlets' areas sum to the assigned polygons' area exactly (110,142,095.1 ha
both), so the accumulation loses and adds nothing.

**Zero area.** 18,489 segments accumulate nothing: 17,478 main-flow segments (8,522 streams, 8,601 km)
on a stream that has a polygon lower down (the polygon they lie in is coded at a lower local code, and
the first rule put it at the top of that lower reach), 1,005 main-flow segments (782 streams, 860 km, 16
of them outlets) on a stream with no polygon at all, and 6 reattached. The plan-time proxy of 129 was
far too low, as the review said: it counted streams with no polygon under their watershed code, and the
miss is at the level of the code pair. By lookup class the zeros are 17,460 "own watershed code, another
local code", 797 "another stream's polygon" (mean polygon 8,092 ha), 228 with no lookup row, 4 own
codes. The no-polygon lines by length: 63 under 100 m, 229 of 100 to 500 m, 193 of 500 m to 1 km, 282 of
1 to 5 km, 15 of 5 to 20 km. This is what decisions 6 (restated) and 7 answer.

**Test side channels.** Each carries what enters it, not the Skeena:

| side channel | segment (measure) | local ha | area ha |
|---|---|---|---|
| 360216952 | 1017.0 to 1676.5 | 23.9 | 1,681.2 (other main-flow water enters at its top) |
| 360216952 | 538.9 to 983.0 | 22.0 | 53,122.7 (plus tributary 360884603, 51,419.5) |
| 360216952 | 0 to 229.3 | 0 | 53,174.5 |
| 360222215 | 0 to 194.0 | 0 | 228,942.8 |
| 360222216 | 465.7 to 962.1 | 19.3 | 228,962.1 |
| 360222216 | 0 to 192.6 | 0 | 229,062.7 |
| 360237491 | 191.8 | 303.2 | 302,913.7 |
| 360237491 | 0 to 100.3 | 0 | 303,115.7 |

87078680, the tributary mouth the lookup gives 4,558,110 ha, carries 302,610.5.

**Basins at the mouth.**

| basin | tree ha | polygons under its code | lookup ha |
|---|---|---|---|
| Skeena (`400`) | 5,440,478.9 | 5,440,334.4 | 5,440,246.5 |
| Nechako (`100.567134`) | 4,725,598.1 | 4,725,795.1 | no row |
| Fraser (`100`) | 23,198,765.7 | 23,215,086.5 | 23,215,081.4 |

The Skeena's tree area is 144.5 ha above the polygons under its code, so a gap step brings in a stream
whose code is not under `400`; the Fraser's and Nechako's are below theirs by what their dead ends and
`no_parent` mouths hold. Phase 4 classes these.

**Against the lookup**, on segments whose lookup polygon has both their codes: main flow equal on
4,299,546, tree lower on 61,704, tree higher on 26,701; reattached lower on 39,567 and higher on 300;
followed lower on 77 and higher on 19. The "higher" class was not expected at plan time; Phase 4 has to
name it.

**Code pairs in more than one run on their line:** 77 pairs (154 polygons, 36,957 ha).

## Plan review: remaining verdicts

| finding | verdict | checked against |
|---|---|---|
| G3: zero-area segments are far more than 129 | right | 18,489 in the prototype; rule restated (decision 6) and the rest asked of the owner (decision 7) |
| G6: a pair that reappears far up a line | right, small | 77 pairs; the lowest run is used |
| G9: the level loop needs a depth index | right | with one, 7 s for 4,380 levels |
| G2, A4: main-river segments beside a side channel differ from the lookup | consistent with the prototype (61,704 lower) | to be classed in Phase 4 |
| A1 to A3, A5, A8, O1, O2, O4: tests that can only pass, and ordering | right, adopted | `task_plan.md`, "Changes after the plan review" |
| G8, A6: the SSNbler step's contract, and that AFV limits cannot detect a wrong area | right by reading; the fork's `afv_edges` not read yet | Phase 5 |
| G10: the fallback's unit must be a piece of a line | not needed | the level loop is fast enough, so the per-line fallback is not built |
| gate question on the exit status | not the owner's | a script's contract; decided in Phase 5 |

## Phase 3: the build (`extras/mainflow_tree/sql/mainflow_tree_area.sql`, 2026-11-20)

Run alone on the existing tree with the server's default settings: 8 min 27 s the first time, 5 min 18 s
once the steps across a gap were worked out only for the 27,000 segments with no node step (the lateral
had been evaluated for all 4.5 million: 2 min 45 s for that statement). The longer steps now: the
main-flow groups and runs 61 s, polygon assignment 83 s, the two sums 21 s each, writing the column to
the tree 39 s.

After rule 1 as restated, 1,171 segments have nothing above them (18,489 before it) and take a length
share. All 19 tests in `sql/qa.sql` print `t`.

One wrong turn: "area never decreases downstream along a blue line" printed `f` on the first run with no
segment breaking it. The test's floor for the number of touching pairs was a guess (over 4 million); the
tree has 2,967,528 (4,510,368 segments less one per line). The floor is now 2 million.

## Phase 4: the tree's area against the lookup, by class (`sql/qa_area.sql`, 2026-11-20)

**How a difference gets its class.** Not from the areas. The lookup routes by codes (`FWA_Upstream`),
the tree by its nodes, and the two can only differ where something upstream is routed differently. Each
such thing is a marker (a line whose mouth the tree takes somewhere its code does not; a polygon given to
a side channel; a length share; a polygon with a bad local code), counted for every segment it passes
going down the tree and for every segment its codes put below it. A segment whose two counts differ has
that kind as its class. The counts are summed down the tree by the same level loop as the area, and by
codes with a cumulative sum per stream. 4 min 21 s.

**The comparison.** Main-flow segments whose lookup polygon has both their codes and whose local code is
in order on their line: 4,362,376.

| | segments | of which differ from the lookup |
|---|---|---|
| nothing upstream routed differently | 4,290,355 | 337 |
| something upstream routed differently | 72,021 | 71,748 (99.6%) |

Of the 337: 155 are lookup rows that are not what the lookup's own definition gives today (the tree
equals the sum over every polygon `FWA_Upstream` puts above the lookup polygon; the stored row is a few
hectares off), 138 are segments whose local code is more than one level below their watershed code, 27
segments whose local code is not under their watershed code, and **17 on 11 lines are not explained**
(3,167 ha of differences in all; HOMA, KHOR, TOOD, USIK, TUTR, OKAN, LBIR, COAL among them). The plan
asked for zero unclassed; the test holds the count at 17 and the README says so.

**Every tree segment that differs from the lookup or has no row, by class** (215,611 rows in
`fwapg.mainflow_tree_area_qa`):

| class | segments | sum of differences (ha) |
|---|---|---|
| reattached (the lookup gives a side channel its river's area) | 58,447 | 39,896,070,604 |
| lookup polygon on the segment's stream at another local code | 53,564 | 99,118,257 |
| several routing kinds at once | 41,016 | 925,536,274 |
| side channel (a tributary the codes count, entering below through a side channel) | 28,892 | 7,951,546 |
| bad code (a polygon whose local code is not under its watershed code) | 16,398 | 1,678,583 |
| lookup polygon on another stream | 7,588 | 829,057,156 |
| edge (a line that leaves BC although its code has a parent in the tree) | 2,928 | 1,096,136 |
| no lookup row | 2,353 | |
| other place (a line whose mouth is on its parent at another place than its code gives) | 1,641 | 1,356,541 |
| share (a length share) | 1,173 | 120,089 |
| local codes out of order on the line | 836 | 45,568 |
| followed | 177 | 60,126,758 |
| side polygon (a polygon given to a side channel) | 162 | 159,775 |
| lookup row not what its definition gives | 155 | 788 |
| segment local code more than one level deep | 138 | 586,553 |
| outlet (a line that ends inside BC) | 95 | 678 |
| segment local code not under its watershed code | 27 | 2,880 |
| not explained | 17 | 3,167 |
| other stream | 4 | 1,186 |

Segments with each routing kind among their classes: side channel 66,535, side polygon 33,207, bad code
31,582, edge 10,868, outlet 7,033, other place 6,739, share 5,173, gap 2,751, other stream 193.

**The build as it stands.** Steps: node 4,483,174, junction 93, line 4, none 27,097. Polygons: `pair`
3,181,977 (93,747,827 ha), `pair_side` 8,431 (407,068 ha), `lower` 1,754 (15,985,977 ha), `ancestor` 22
(2,130 ha); unassigned 53,209 with no stream (838,871 ha, of which 667 ha went out as length shares) and
60 under `999` (3,623 ha). Length shares: 869 segments, 154,217 ha, out of 494 polygons. 1,457 polygons
(45,175 ha) have a local code that is not under their watershed code; they are placed at their stream's
mouth.

**Wrong turns, kept.**

- The first class list had "local codes out of order" for a whole stream with any inversion. That put
  60,618 segments in it, with the Fraser, Skeena, Stikine and Nechako main stems among 1,670 streams, and
  took most of every large river out of the comparison (the review's A4). It is now per segment (no
  segment above with a lower code, none below with a higher one): 836.
- 5,009 segments differed with nothing routed differently. Tracing one (38 ha, `900.102882`) found a
  polygon whose local code is not under its own watershed code. `FWA_Upstream` has guards that leave such
  a polygon out, so the lookup counts it nowhere; my reading of `FWA_Upstream` from memory had missed the
  guards. That became the `bad code` kind (and the polygon's place: its stream's mouth).
- Tracing another (147 ha, a line in MILL) found a defect in the build: a 6010 connector with no local
  code ended the run it sat in, so the polygon stopped at the connector and the segments above it had
  none. Fixed (the connector is left out of the runs); length shares fell from 1,171 to 869 segments.
- A third (5 ha, a chain in GRNL) had the tree equal to the lookup's own definition and the stored row
  short: the lookup table is stale there. Recomputing the definition for the leftover segments is now a
  step of `qa_area.sql`.
- A bad-code polygon at its stream's mouth reach was still counted by the marker; `FWA_Upstream`'s
  mouth-reach case asks for the local code to be under the reach's. Following it took the unexplained
  from 37 to 17.

**Restore the bug.** `scripts/08_restore_the_bug.py` breaks what each of the 13 new tests guards, in a
transaction that is rolled back, and runs the test's own statement: all 13 print `f`, including the
defect the issue is about (the lookup's 5,059,365 ha written onto a side-channel segment).

One mistake in the session itself: an edit script failed its own check and the commands after it ran
anyway (joined with `;`), so a 5-minute build ran on unchanged files. Steps are joined with `&&` since.

## Phase 5: SSNbler end to end (2026-11-20, the fork at 37ca338)

`pak::pak("NewGraphEnvironment/SSNbler@37ca338")` installed 1.1.2.9000. The first try failed with "Could
not solve package dependencies"; several lines down the cause was "Bad GitHub credentials": the token in
the shell's environment is rejected, and the install of this public repo worked with it unset.

The area step (`SSNBLER_AREA=1`): `afv_edges(infl_col = "upstream_area_ha")`, `sites_to_lsn` and
`afv_sites` on the midpoints of up to 200 edges, exit status 6 on failure.

| subset | lines | minutes | peak GB | node errors | outlets | AFV | side channel mouths held, largest share |
|---|---|---|---|---|---|---|---|
| tributary 360884603's basin (`400.107640`) | 3,190 | under 1 | 0.8 | 0 | 1 | 2.43e-05 to 1 | none |
| KLUM (`400`, group KLUM) | 24,732 | 8 | 28.0 | 0 | 1 | 1.29e-07 to 1 | 2 (360222216, 360237491), 0.0665 |

Both ran with no overrides, 200 sites each with a value in (0, 1].

**Control** (`scripts/09_ssnbler_lookup_control.R`, on KLUM's network): with the tree's area the mouths
of 360222216 and 360237491 take 0.0477 and 0.0665 of their confluence; with the watershed lookup's area
both take 0.5, which the step's limit of 0.2 fails. The limits the issue names (values in (0, 1], 1 at
the outlet) hold for any positive areas, so this is the check that can tell (the review's A6).

**The whole Skeena is hours.** The control ran `afv_edges` twice on 24,732 edges in 7 min, so about
3.5 min each. For every edge it finds the path to the outlet and tests every edge's membership in it, so
its time grows with the square of the edge count: 262,000 edges is about 112 times KLUM, about 6.5 h,
after the 54 min `lines_to_lsn` took on the fork. Its memory at that size is not measured.

## Phase 7: the whole job, and review round 1 (2026-11-20)

**`./mainflow_tree.sh` end to end** on the provincial database, before round 1's fixes: exit 0, every test
`t`, 46 min 34 s (15:49:56Z to 16:36:30Z). `data/qa_topology.csv` was written at 16:25Z, so the blue line
paths, the tree and the topology QA took about 35 min and the area build, the comparison, the tests and
the export about 11. Another session was running its tests on the database throughout. The export has
five columns, `upstream_area_ha` last.

**Round 1** (`review-round1.md`, a reading round: the job was being timed). Twelve findings; verdicts:

| finding | verdict | what was done |
|---|---|---|
| the basin and side-channel tests use `bool_and()`, which skips a NULL member | right | counted with `FILTER` instead |
| `lower` and `ancestor` polygons can land on a side channel, with no marker | right: 56 `lower` (158,932 ha) and 2 `ancestor` (2 ha) polygons were on reattached segments | rules 3 and 4 read main-flow reaches only; the marker is by where a polygon is, not by its rule |
| "`FWA_Upstream` leaves them out, so the lookup counts them nowhere" | right, it was wrong as written | the function has guards in two of its three cases: out at the mouth reach and on ancestors the local code is not under |
| the lowest-run fix was in rule 1 only | right | `area_reach` takes the lowest run of the exact pair |
| the SSNbler side-channel check holds three literal ids and says nothing when it holds none | right | the three ids checked against the network (each a mouth, measure 0); the line now says "none in this subset, not checked"; the step refuses edges with no `linear_feature_id` |
| a segment that gives a share can be left with float noise as its whole area | possible, not live: 5 givers are left with 0 to 1.8e-15 ha of their own, all with inflow | `greatest(..., 0)`, and the share test refuses a giver whose whole area is under 1e-6 ha |
| figures quoted for the final build that the record holds only for the prototype | right | re-measured below, by `scripts/10_final_figures.sql` |
| float sums in no fixed order | right, measured: two builds of the same code gave different column checksums (`bad9bb4a…`, `e6438e4c…`) | every sum ordered; two builds since give the same (`92bd48cb…`) |
| `no stream` assigned by elimination | right, and it hid something: 3 polygons (14 ha) lie below the lowest tree segment of their stream (SIML and KUSR; the stream leaves BC further down). Two of them had been given to a side channel by the `ancestor` rule | classes are now the property they name; the new class is `below the tree` |
| exit 0 not tied to an `area: ok` line | right, no live route | tied |
| "run after" headers short | right | fixed |
| `ADD COLUMN IF NOT EXISTS` takes its lock before it looks | right, low | added only where the column is missing |

**The build after round 1** (`scripts/10_final_figures.sql`, 2026-11-20T17:00Z, column checksum `92bd48cb…`):
polygons `pair` 3,181,977 (93,747,827 ha), `pair_side` 8,431 (407,068), `lower` 1,754 (15,985,977),
`ancestor` 20 (2,128); unassigned `no stream` 53,208 (838,859 ha, 667 out as shares), `999` 60 (3,623),
`below the tree` 3 (14). Steps node 4,483,174, junction 93 (90 dead ends, 3 cut-offs), line 4 (cut-offs),
none 27,097. Outlets: BC's edge 26,690 (109,953,592 ha, largest 23,198,718), dead ends 383 (184,499 ha,
largest 50,535), `no_parent` 23 (5,360), cut-off 1 (217); 110,143,668 ha in all, depth to 4,380. Side
channels: 360216952 1,681.2 above the entry, 53,122.7 below, 53,174.5 at the mouth; 360222215 228,962.1;
360222216 228,962.1 and 229,062.7; 360237491 302,913.7 and 303,115.7; 87078680 302,610.5. Tributaries by
the polygons under their code: 51,419.5, 228,942.8, 302,610.5. Basins at the mouth against the polygons
under their code: Skeena 5,440,478.9 / 5,440,334.4, Nechako 4,725,598.1 / 4,725,795.1, Fraser
23,198,717.8 / 23,215,086.5. Shares 869 segments, 154,217 ha, 494 polygons, median 45.3 ha, largest
37,633. Bad-code polygons 1,457 (45,175 ha). The comparison's counts and classes are as in Phase 4
(4,362,376 / 4,290,355 / 337 / 72,021 / 71,748; 17 not explained on 11 lines, 3,169 ha). All 23 tests
print `t`; all 13 restore-the-bug checks fire.

## Review round 2 (2026-11-20, `review-round2.md`; with the database)

Round 1's fixes held on every probe; about 60 quoted figures were re-derived by the reviewer and agree;
ten defects restored in rolled-back transactions each printed `f`. Three findings:

| finding | verdict | what was done |
|---|---|---|
| no test fails when round 1's second finding is put back (56 `lower` polygons moved back onto side channels, areas corrected down both chains: every area test still `t`) | right: "only rule 2 gives a polygon to a side channel" was held by the joins alone | new test: every polygon is on a segment its rule allows, read from the polygon's and the segment's codes; its defect check fires |
| a polygon whose codes are on no segment never took rule 1's run, though main-flow segments sit in its code range: 96 polygons, 459 segments (837 km) | right; a rule question, put to the owner | decision 8: method `range`. The reviewer's example (blue line 360884436, measure 7,642 to 9,149) read 127 to 277 ha, the top from a length share; it reads 1,080 to 1,229 ha now |
| "158,188 network segments" with no local code dropped its condition | right | "whose watershed code is not under `999`" restored (328,961 have no local code in all) |

Also from its notes: the Fraser is 0.0705% from its polygons, so "within 0.08%" now; 632 `pair_side`
polygons (20,055 ha) are on a pair several side channels share and go to the lowest `blue_line_key`
(README caveat).

**The build after round 2** (`scripts/10_final_figures.sql`, 2026-11-20T17:50Z, column checksum
`4c1120f5…`): polygons `pair` 3,181,977 (93,747,827 ha), `pair_side` 8,431 (407,068), `range` 96
(1,129,808), `lower` 1,658 (14,856,168), `ancestor` 20 (2,128); unassigned as after round 1. Steps,
outlets, side channels and basins as after round 1 (the totals at the outlets are 110,143,668 ha).
Shares 803 segments, 112,519 ha, 458 polygons, median 46.6 ha, largest 5,690 (the 37,633 ha share is
gone: its polygon now goes to the segments in its range). Comparison: 4,362,376 comparable, 4,290,356
routed alike of which 337 differ, 72,020 routed differently of which 71,747 differ; 215,648 rows in
`fwapg.mainflow_tree_area_qa`: reattached 58,447, followed 177, lookup polygon at another local code
53,560, on another stream 7,588, no row 2,353, one routing kind 51,292 (side channel 28,892, bad code
16,398, edge 2,928, other place 1,641, share 1,172, side polygon 162, outlet 95, other stream 4), several
kinds 41,016, local codes out of order 878 (339 with the tree higher, 539 lower), lookup row not its
definition 155, segment code anomalies 165, not explained 17 on 11 lines (3,169 ha). "Local codes out of
order" rose from 836 to 878: a polygon placed by position on a line whose codes run out of order. The
area build took 5 min 40 s and 5 min 42 s on the last two runs. All 24 tests print `t`; all 15
restore-the-bug cases fire.

## Review round 3 (2026-11-20; `review-round3.md`, cut short at 19:17Z, and `review-round3b.md`)

Two reviewers, because the first passed its 60 minutes (it was restoring a defect for every rule; it
returned at 87 minutes after being asked to write up). Both found the same defect inside round 2's fix.

**The `range` rule put most of its area in the wrong place.** Of its 96 polygons (1,129,808 ha), the
segment each landed on touched the polygon for 29 (187,151 ha); the `lower` segment it had before touched
for 11 (1,089,958 ha). Three cross-border polygons carried it: 1000002557 (BEAV, 766,913 ha) moved to a
1.46 km line because two blue lines share a watershed code and their route measures were compared, so
eight Beaver River segments read 924 to 5,333 ha where the lookup has about 780,000; 1000002001 (TATR,
105,986 ha), local codes out of order; 1000003707 (SWIR, 63,375 ha), a segment whose local code is not
under its watershed code sorting above every polygon code. The 42 new "local codes out of order"
segments were this, not what the record said ("a polygon placed by position": it was placed by a code).

This was my mistake before it was the rule's. I recommended the rule to the owner saying areas would
change on those 459 segments and nowhere downstream, on the strength of one example, without measuring.
The reviewer's "459 segments (837 km)" also measures as 540 km.

**The mechanism, and how far it reached.** Both reviewers named it: a relation between codes was taken
for a place. Measured by geometry (is the segment's midpoint inside the polygon; does the segment touch
it) on the build before the fix:

| rule that moves a polygon away from the place its codes give | polygons | on a segment whose midpoint is inside | on a segment that does not touch |
|---|---|---|---|
| rule 1, up the line through reaches with no polygon | 23,897 (3,989,156 ha) | 15,412 (3,538,225 ha) | 6,368 (largest 15,670 ha) |
| rule 3, `range` | 96 (1,129,808 ha) | 9 (154,563 ha) | 67 (largest 766,913 ha) |
| rule 2, `pair_side` | 8,431 (407,068 ha) | 1,467 (97,711 ha); another side-channel segment of the pair inside for 358 more | 5,470 (247,103 ha) with no side-channel segment of the pair in or touching |
| bad-code polygons sent to their stream's mouth | 1,454 (45,105 ha) | | 530 do not touch the mouth segment (largest 940 ha); left as is: the mouth is below wherever the polygon is on its stream |

**What was done.** A polygon leaves the place its codes give only for a segment that lies in it (midpoint
inside): rule 1 up its line to the highest such segment; rule 3 only where one exists; rule 2 (the owner's
decision 9, asked) only where a side-channel segment of the pair lies in it. `area_reach` takes the line
with more segments of the code before comparing anything across lines. A new test checks it by geometry;
the placement test stays. The comparison's markers are now compared as sets, not counts.

**Why sets.** After the rule changes the unexplained segments went from 17 to 323, 293 of them on the
Nechako main stem each 1.7 ha low. Tracing found no misplaced polygon: with 1,899 length shares instead
of 803, a marker the tree has and the codes lack cancelled one the other way round. With each marker
given a number of its own (in a 2^64 slot per kind, summed exactly) the unexplained are 1 segment
(TUTR, 1.6 ha), and the 17 of earlier builds were mostly the same cancellation.

**The owner's question while deciding** (2026-11-20): is this a floodplain issue, and should side
channels and floodplains be explored together in their own issue, with mapped floodplain showing which
segments intersect? The numbers say yes: the polygons in question are about 45 ha, with codes only on
side-channel segments, mostly beside the river and not touching the side channel. Filed as its own issue
(see progress).

**The build after round 3** (`scripts/10_final_figures.sql`, 2026-11-20T20:15Z, column checksum
`c0b270f3…`): polygons `pair` 3,181,977 (93,747,827 ha; 15,867 of them, 3,547,842 ha, above their own
reach), `pair_side` 1,825 (108,013), `range` 11 (154,608), `lower` 8,332 (16,130,088), `ancestor` 20
(2,128); unassigned `no stream` 53,208 (838,859 ha, 667 out as shares), `999` 60 (3,623), `below the
tree` 20 (351: the 3 from round 1 and 17 whose codes are only on a side channel that does not lie in
them, with no main-flow reach below). Steps as before. Outlets: BC's edge 26,690 (109,958,939 ha,
largest 23,203,431), dead ends 383 (179,414, largest 50,535), `no_parent` 23 (4,761), cut-off 1 (217);
110,143,331 ha in all. Side channels: 360216952 1,579.6 above the entry, 53,006.5 below, 53,058.3 at the
mouth; 360222215 228,962.1; 360222216 228,962.1 and 229,062.7; 360237491 302,610.5 and 302,812.5;
87078680 302,610.5. Basins: Skeena 5,440,478.7, Nechako 4,725,748.7, Fraser 23,203,431.2 (polygons under
their code 5,440,334.4, 4,725,795.1, 23,215,086.5). Shares 1,899 segments, 181,108 ha, 1,116 polygons,
median 13.7 ha, largest 37,633. Comparison: 4,362,376 comparable; 4,288,277 routed alike, 293 of them
differ (154 lookup row not its definition, 138 segment code more than one level deep, 1 not explained);
74,099 routed differently, 73,808 differ; 217,655 rows: reattached 58,447, followed 177, lookup polygon
at another local code 53,591, on another stream 7,587, no row 2,353, one kind 57,134 (side channel
32,740, bad code 16,525, share 3,212, edge 2,926, other place 1,627, outlet 95, side polygon 5, other
stream 4), several kinds 37,581, local codes out of order 492. All 25 tests print `t`; all 16
restore-the-bug cases fire.

**From the first reviewer's enumeration (48 rows, unfinished):** the sum tests (additive, never
decreasing, outlets sum to the area assigned, positive) are true of any assignment once summed, so they
cannot see a polygon moved between segments; what can is the placement test, the geometry test and the
comparison with the lookup, which `mainflow_tree.sh` runs before the tests. Held by the code alone, or by
the comparison only: the order of rules 2 and 3 where both could apply; which run of a reappearing pair
is taken; rule 2's tie-breaks.

## Review round 4 (2026-11-20, `review-round4.md`): the enumeration

The reviewer re-derived every polygon's code position, and every move away from it, with its own
queries, and compared with the build, for all 3,245,453 polygons (commit 6dcacac):

| method | polygons (ha) | at code position | elsewhere | elsewhere: midpoint inside | elsewhere: not touching |
|---|---|---|---|---|---|
| `pair` | 3,181,977 (93,747,827) | 3,166,110 | 15,867 (3,547,842 ha) | 15,867 | 0 |
| `pair_side` | 1,825 (108,013) | 0 | 1,825 | 1,825 | 0 |
| `range` | 11 (154,608) | 0 | 11 | 11 | 0 |
| `lower` | 8,332 (16,130,088) | 8,332 | 0 | | |
| `ancestor` | 20 (2,128) | 20 | 0 | | |
| unassigned | 53,288 (842,833) | 53,288 (no rule gives a segment) | 0 | | |

So the mechanism of rounds 1 to 3 (a relation between codes taken for a place) has no instance left:
every polygon away from its code position is on a segment that lies in it. This is what ends the loop.
Where a tie-break was needed the reviewer used the documented one, so agreement shows the build does
what it says, not that the tie-break is right.

Its findings, each fixed:

| finding | what was done |
|---|---|
| one polygon (9941495, TATR, 9,674 ha) where a side-channel segment and 18 km of main flow both lie in it went to the 48 m side-channel segment; 76 main-flow segments read about 9,400 to 12,000 ha low | main flow comes before a side channel (`range` before `pair_side`); checked by comparing placements before and after: exactly this polygon moved |
| "a bad-code polygon sits at its stream's mouth" is not true of 22 of 1,457 | reworded: placed as if its local code were the mouth's (19 then go up their line by rule 1, 3 are `ancestor`) |
| the largest length share's polygon is 42,667 ha, not "that size" | corrected |
| tie-breaks the text did not state (rule 3 across lines; rule 2's side-channel pick; rule 1 passing a segment with its own polygon) | stated in the README and the SQL header |
| SQL comments left behind where the README was rewritten | fixed |
| marker weights: a 40-bit hash is not guaranteed unique | 48 bits, and the comparison stops if two markers share a number or a kind has 65,536 markers or more |

**The build after round 4** (column checksum `a7fe4b7c…`): as after round 3 except `pair_side` 1,824
(98,338 ha), `range` 12 (164,282 ha), shares 1,898 segments (181,075 ha). The comparison's counts and
classes are unchanged. All 25 tests print `t`; all 16 restore-the-bug cases fire.

## Review round 5 (2026-11-20, `review-round5.md`): the changes since round 4

One finding, the mechanism once more in a narrower place: "no main-flow segment in the polygon's code
range lies in it" had been taken for "no main-flow segment lies in it". Of 1,824 `pair_side` polygons,
1,181 hold the midpoint of a main-flow segment: for 1,177 it is another stream's main flow only (a
tributary crossing to the side channel), and 4 polygons (2,478 ha: BABL 7706821 with 2,323.5 ha, REVL,
COAL, KHOR) held main flow of their own watershed code. Fixed: rule 3 skips a polygon that a main-flow
segment of its own watershed code lies in. Checked by comparing placements before and after: exactly
those four moved, to `lower`. A test now counts, by geometry, polygons on a side channel that hold their
own stream's main flow (0), and its defect check fires. Wording that said more than the code did is
corrected in the SQL header, the README and the tests' comments.

Everything else the round checked holds: SSNbler's values equal the plain arithmetic to 3.9e-16 on the
3,190-edge basin (re-run by the reviewer on a copy of the finished network); the new province-wide test
prints `f` with the lookup's area restored on the side-channel segments (760 of 16,745 under a fifth,
median 0.5000) and `t` after rollback; the swap keeps every polygon whose pair is on main flow as `pair`;
the weights' two conditions are the right ones; every figure it re-derived agrees.

**How the review ended.** Rounds 3, 4 and 5 each found a defect inside the previous round's fix, all of
one mechanism, so a quiet round could not end it. What ends it is the enumeration: every polygon that
is away from the place its codes give (17,699 of 3,245,453) is on a segment whose midpoint is inside it,
and no polygon on a side channel holds main flow of its own stream. Round 4 re-derived the first over
every polygon with its own queries; both are now tests over the whole set, by geometry, and each fires
when its defect is restored. Seven reviewer agents in all (the Plan review, rounds 1 to 5, and a
replacement for round 3), past the usual five: rounds 3 to 5 each found a real misplacement, the largest
780,000 ha on the wrong river.

**The final build** (`scripts/10_final_figures.sql`, 2026-11-20T21:38Z, column checksum `0e553e9e…`):
polygons `pair` 3,181,977 (93,747,827 ha; 15,867 of them, 3,547,842 ha, above their own reach), `range`
12 (164,282), `pair_side` 1,820 (95,860), `lower` 8,336 (16,132,566), `ancestor` 20 (2,128); unassigned
`no stream` 53,208 (838,859), `999` 60 (3,623), `below the tree` 20 (351). Steps node 4,483,174,
junction 93, line 4, none 27,097. Outlets: BC's edge 26,690 (109,958,939 ha, largest 23,203,431), dead
ends 383 (179,414, largest 50,535), `no_parent` 23 (4,761), cut-off 1 (217); 110,143,331 ha in all. Side
channels and basins as after round 3. Shares 1,898 segments, 181,075 ha, 1,116 polygons, median 13.7,
largest 37,633 (of a 42,667 ha polygon). Comparison: 4,362,376 comparable; 4,288,277 routed alike, 293
of them differ (154, 138, 1 not explained); 74,099 routed differently, 73,808 differ; 217,655 rows:
reattached 58,447, followed 177, another local code 53,591, another stream 7,587, no row 2,353, one
kind 57,136 (side channel 32,742, bad code 16,525, share 3,212, edge 2,926, other place 1,627, outlet
95, side polygon 5, other stream 4), several kinds 37,579, out of order 492. Side channels where they
meet main flow (`scripts/11_side_channel_share.sql`): 16,745 places; with the tree's area the median
share of the confluence is 0.50% and 15,864 are under a fifth (210 between 0.4 and 0.6); with the
lookup's area the median is 50.0% and 15,261 of 16,034 are between 0.4 and 0.6 (390 under a fifth). All
27 tests print `t`; all 18 restore-the-bug cases fire.

## Phase 5, final: the SSNbler suite (2026-11-20, the fork at 37ca338, the final build)

The owner asked for no whole-Skeena run and the suite that tells the most. Each run: `SSNBLER_AREA=1
./ssnbler_check.sh 34 <name> <wscode> [group] [outlets]`, one at a time, 0 node errors, no overrides, 200
sites with a value in (0, 1], and SSNbler's `afvArea` and `areaPI` equal within 1e-9 to plain arithmetic
on every edge (the reviewer measured the difference on the smallest at 3.9e-16).

| subset | lines | minutes | peak GB | outlets | AFV | side channels held |
|---|---|---|---|---|---|---|
| `400.107640` | 3,190 | under 1 | 0.6 | 1 | 2.43e-05 to 1 | none |
| `400`, KLUM | 24,732 | 8 | 28.0 | 1 | 1.29e-07 to 1 | 2, largest share 0.0664 |
| `400.431358` (Bulkley, parallel path) | 52,293 | 21 | 2.8 | 1 | 1.9e-07 to 1 | none |
| `100.567134`, LTRE | 8,484 | 1 | 3.1 | 3 | 5.35e-07 to 1 | none |

LTRE: by the build's pointer the subset has one way out and two steps across a gap (two dead ends);
SSNbler, which sees geometry only, has three outlets. The three subsets' areas were checksummed before
and after round 5's rebuild and are unchanged, so the runs describe the final build.

One mistake found on the way: the check's literal for 360216952 was its mouth segment (123041439), which
flows into another side channel (360216962) and has a share of 1; the place its water meets the Skeena
is 123043588, share 0.0104. On LSKE the first would have failed the step for the wrong reason. Not run:
LSKE (about 29,000 lines, serial path, more memory than was free beside the database) and the whole
Skeena (`afv_edges` is quadratic: hours).

## Errors Encountered

| Error | Resolution |
|-------|------------|
| A classification query with a correlated `EXISTS` over 3.2 million polygons ran 12 min without finishing (`03_lookup_classes.sql`, query D) | Cancelled; the prototype's assignment answers the same question in 1 min 40 s with an indexed lateral lookup |
| A test written with a subquery per row over `fwapg.mainflow_tree_area` by `downstream_id` (no index) did not finish in 10 minutes for 16,745 rows | Written as a join; 42 s for the whole test file |
| Piping `psql` through `grep` to a file hid rows until exit (grep block-buffers when not on a terminal) | Read the result after the command ends, or write psql's output to the file directly |
