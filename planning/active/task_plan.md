# Task: Upstream area on the main-flow tree, so SSN additive functions need no hand overrides (#4)

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

Branch `4-upstream-area-on-the-main-flow-tree-so-s` off `origin/newgraph` (28fb2ac), PR into `newgraph`.

## Context

The main-flow tree (`whse_basemapping.fwa_stream_networks_mainflow_tree`, 4,510,368 segments, built by
`extras/mainflow_tree`) has no upstream area. The two ways to get one today both give a different answer
on the segments the tree exists for:

- `FWA_WatershedAtMeasure()` on a side channel returns the main river's area, a sliver, or nothing.
- The lookup (`fwa_streams_watersheds_lut` + `fwa_watersheds_upstream_area`) gives a side channel its
  river's area (360216952 reads 5.1 million ha, the Skeena's; the tributary that enters it has 51,420 ha),
  matches 8,111 tree segments to a polygon of another stream's code, and has no row for 2,941.

So SSN additive function values still need hand overrides. The outcome wanted: one area per tree segment,
built and tested with the tree, that SSNbler's `afv_edges(infl_col = ...)` takes as it stands.

Measured at plan time (2026-11-20, read-only, local provincial database, PostgreSQL 17.5):

| | |
|---|---|
| polygons whose codes are on a main-flow tree segment | 3,180,734 (93,501,694 ha) |
| polygons whose codes are on a reattached or followed segment only | 8,449 (407,571 ha) |
| polygons whose watershed code is in the tree, local code not | 2,985 (54,929 ha) |
| polygons whose watershed code is not in the tree | 53,225 (841,820 ha) |
| polygons under `999` | 60 (3,623 ha) |
| main-flow tree segments on a stream with no polygon at or under its code | 129 (84 streams, 92 km) |

The four test side channels' tree segments all read 4.26 to 5.11 million ha through the lookup; the
tributaries that enter them read 51,420, 228,943 and 302,611 ha, as the issue says. Tributary 360881231's
mouth segment (87078680) reads 4,558,110 ha, the next segment up 302,611.

No file in the repo loads the tree's export (`load.sh` does not), and the export is gitignored, so a new
column changes no loader.

## Decided at the gate

Decisions 1, 2, 4 and 5 were answered by the owner at the plan gate on 2026-11-20, each as recommended.
Decisions 3 and 6 are defaults stated in the plan and approved with it.

1. **Approach: A, accumulate over the tree.** Each `fwa_watersheds_poly` polygon is given to one tree
   segment, and area is summed downstream through the tree's own nodes. B (the lookup, patched in three
   classes: 58,447 reattached, 8,111 wrong-stream, 2,941 missing) is not built.
2. **Storage: a column `upstream_area_ha` on the tree table**, with the working table
   `fwapg.mainflow_tree_area` (pointer, local area, method) kept for QA, as `fwapg.mainflow_tree_qa` is.
3. **Units: hectares, `double precision`, not rounded**, as `fwa_watersheds_upstream_area` stores them.
   Taken as the conventional default, not asked.
4. **Gaps: area is carried across the tree's dead ends and cut-offs** to the parent line the blue line
   paths name (473 + 8), so a river's area includes a tributary whose mouth does not touch it. The step is
   recorded by method (`node` or `junction`). The 23 `no_parent` mouths and BC's edge stay outlets.
5. **`FWA_WatershedAtMeasure()`'s empty answer on side channels: measured in Phase 1 and filed as its own
   issue**, not fixed on this branch (a function fix is a migration and a candidate for upstream, which
   has its own branch rules).
6. **Polygon assignment rule** (follows the lookup's convention, area at the polygon's outlet, so main
   flow can agree with it): a polygon goes to the uppermost tree segment that shares its watershed and
   local codes, main flow before reattached; failing that, to the tree segment on its watershed code at
   the next local code below; failing that, to its nearest ancestor code in the tree at the position its
   own code gives; anything left is listed by class in a table and counted by a test. Phase 1 measures
   each class before the rule is built, and a class the rule misplaces comes back as a question.

## Phase 1: Measure what the issue says, on the database as it is now

One-off SQL lives in `planning/active/scripts/`, numbers in `findings.md`.

- [x] Re-measure Problem 1: `FWA_WatershedAtMeasure()` at the issue's nine points (blue line, measure),
      polygons returned and area
- [x] Trace the empty answers (360216952 at 1800 to 3300) to the branch of the function that returns no
      row, and say whether it is #49's defect (that one raises `more than one row`, so likely not)
- [x] File what the trace finds as its own issue on NewGraphEnvironment/fwapg (decision 5), linked from #4
      (#52)
- [x] Re-measure Problem 2: tree segments by lookup class (polygon of its own code, another stream's, no
      row) by `source`, against the issue's 8,111 and 2,941
- [ ] Break down the 53,225 polygons whose watershed code is not in the tree and the 2,985 whose local
      code is not (dropped side channels, waterbodies, coast, cross-border), and settle decision 6's
      fallback steps on those numbers
- [ ] Count tree segments with no polygon at or above them (plan-time proxy: 129), and say what area they
      get; a zero is not allowed by the issue's first criterion, so the rule for them is written here

## Phase 2: Tests first, in `extras/mainflow_tree/sql/qa.sql`

Each is `SELECT '<name>' AS test, <boolean> AS result`, non-NULL over no rows (`mainflow_tree.sh` fails on
`name|`). They fail until Phase 3.

- [ ] Every tree segment has a non-null, positive `upstream_area_ha`
- [ ] Additive at every node: a segment's area is its local area plus the areas of the segments that
      flow into it (node and junction steps), within float tolerance
- [ ] Non-decreasing downstream along every pointer
- [ ] Conservation: each polygon is assigned at most once; assigned plus listed-unassigned area equals
      the polygons' total; the areas at the tree's outlets sum to the assigned area
- [ ] Independent of the pointer: the Skeena's area at its mouth equals the area of the polygons under
      `400` that are assigned, and the same for the Nechako (`100.567134`) with its listed outlets
- [ ] The four Skeena side channels below their entry carry the entering tributary's area (51,420;
      228,943; 228,943 through 360222215; 302,611 ha) plus only polygons listed as their own
- [ ] 87078680 (the tributary mouth the lookup gives 4,558,110 ha) carries the tributary's area
- [ ] Main flow agrees with the lookup wherever the polygon is the segment's own and nothing reattached
      or carried across a gap lies above; every other difference has a class (zero unclassed)
- [ ] Control: the lookup differs from the tree on the reattached segments by more than a floor, so the
      comparison is shown able to fail
- [ ] Ceilings on the unassigned classes and on junction steps, at the measured counts

## Phase 3: Build the area

New file `extras/mainflow_tree/sql/mainflow_tree_area.sql`, in the style of `sql/mainflow_tree.sql`.

- [ ] Downstream pointer over tree segments: the tree segment whose upstream node is this segment's
      downstream node, nodes at 1 cm (the rule and the `PRIMARY KEY (up_x, up_y)` assertion from
      `planning/archive/2026-10-issue-34-measure-downstream-queries/scripts/sql/01_downstream_ids.sql`)
- [ ] Junction steps for dead ends and cut-offs from `fwapg.blk_parents` (decision 4), each with its
      method; refuse a cycle (every segment reachable from an outlet, as
      `extras/pcic_crosswalk/sql/pcic_crosswalk06_subbasins.sql` checks its tree)
- [ ] Assign polygons to segments by decision 6; unassigned polygons to
      `fwapg.mainflow_tree_area_unassigned` with a class
- [ ] Local area per segment, then accumulate from the top of the tree down by depth (the level loop of
      `pcic_crosswalk06_daily.sql`); if that is not minutes, sum along each blue line first and loop over
      lines
- [ ] Write `upstream_area_ha` to the tree table and keep `fwapg.mainflow_tree_area`
      (`linear_feature_id`, `downstream_id`, `downstream_method`, `local_area_ha`, `upstream_area_ha`)
- [ ] Run it from `mainflow_tree.sh` after `sql/mainflow_tree.sql`; record its time against the job's
      20 min
- [ ] Restore-the-bug check for each new test: break the thing it guards in a copy and see it print `f`

## Phase 4: Compare with the lookup, by class

- [ ] `sql/qa_area.sql`: every tree segment whose area differs from the lookup's, with one class each
      (reattached side channel, side channel above, polygon of another stream's code, no lookup row, gap
      above, polygon assigned by a fallback step), kept as `fwapg.mainflow_tree_area_qa` and exported to
      `data/qa_area.csv` beside `data/qa_topology.csv`
- [ ] Counts and area by class into `findings.md`; an unclassed difference is a defect in the build or a
      class to name, not a tolerance to widen
- [ ] Update #33's body: what the tree's area needs from the lookup after this (nothing, under A) and
      what stays open there

## Phase 5: SSNbler end to end

The SSNbler installed where this runs is 1.1.2 with no GitHub remote recorded, so the pinned fork is
installed first. One run at a time, under `ssnbler_check.sh`'s cap, memory measured not estimated; a run
that reaches the cap is repeated on a machine with more memory instead of with a higher cap.

- [ ] Install the pinned fork: `pak::pak("NewGraphEnvironment/SSNbler@37ca338")`
- [ ] `ssnbler_check.sh`: the export carries `upstream_area_ha`; an optional argument turns the area step
      on; the `runs.log` line carries its result; the exit statuses keep their meanings
- [ ] `ssnbler_check.R`: optional step after `lines_to_lsn`: `afv_edges(infl_col = "upstream_area_ha")`,
      a fixed sample of sites through `sites_to_lsn` and `afv_sites`; fail on a zero or missing area
      warning, an AFV outside (0, 1], or an outlet edge whose AFV is not 1
- [ ] KLUM (three of the four test side channels), then the whole Skeena, no overrides; numbers
      (lines, minutes, peak GB, AFV range) into `findings.md`

## Phase 6: Documents

- [ ] `extras/mainflow_tree/README.md`: the rule for area, the Output table, Processing and its time,
      Results by class, the SSNbler area step, and the caveat line that points at #4 replaced
- [ ] `research/fwa_mainflow_tree.md`: the "Not settled" line becomes a section on area (what the lookup
      gives and why, the assignment rule, the classes, what crossing gaps changes); `Verified`, `Issues`
      and `Produced by` updated
- [ ] `research/README.md`: the row's topic gains area

## Phase 7: Whole job, review, PR

- [ ] `./mainflow_tree.sh` end to end on the provincial database, when no other job is writing to it
      (it rebuilds the blue line paths and drops the tree table); every test `t`; time recorded
- [ ] `/code-check branch`, fixes as follow-up commits
- [ ] `/planning-archive` with a README that carries Measurement and Evidence, wrong turns kept
- [ ] `/gh-pr-push` with `--base newgraph`

## Owed at the end (reported, done after merge)

- [ ] Close #4 by hand with a comment naming the PR (`Closes` does not act on a merge into `newgraph`)

## Validation

- [ ] Tests pass (`sql/qa.sql`, every line `|t`, inside `mainflow_tree.sh`)
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved: the area by the tests of Phase 2, two of which do not use the pointer that
built it (basin totals from polygon codes, and the lookup on the class where it should agree); each new
test by restoring the defect it guards; the SSNbler step by a clean KLUM and whole-Skeena run with no
overrides; the job's cost by its recorded time.

## Not in scope

Merging segments into longer SSN edges; covariates other than area; filling the lookup (#33); a stored
`downstream_id` for general use (#36 decides the default downstream walk); the function fix for
`FWA_WatershedAtMeasure()`.

## Critical files

- `extras/mainflow_tree/mainflow_tree.sh`, `sql/mainflow_tree.sql`, `sql/qa.sql`, `sql/qa_topology.sql`
- new: `extras/mainflow_tree/sql/mainflow_tree_area.sql`, `sql/qa_area.sql`
- `extras/mainflow_tree/ssnbler_check.sh`, `ssnbler_check.R`, `README.md`
- `research/fwa_mainflow_tree.md`, `research/README.md`
- read, not changed: `load/fwa_streams_watersheds_lut.sql`,
  `extras/lookups/sql/fwa_watersheds_upstream_area.sql`, `extras/blue_line_paths/sql/blue_line_paths.sql`

