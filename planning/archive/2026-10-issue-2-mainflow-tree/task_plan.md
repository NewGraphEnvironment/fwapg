# Task: Main-flow tree: a dendritic stream network computed from FWA (#2)

FWA is not a tree: braids and side channels are mapped as secondary flow, so nodes split downstream. That is correct cartography, but SSNbler rejects it, and the obvious filter (drop the secondary-flow edge types) both leaves splits and cuts tributaries off.

Measured on 14 watershed groups (KLUM LSKE MSKE KISP BULK MORR BABL ZYMO NECR CHES LCHL UNRS STUR FRAN), edge type 1425 excluded. A *split* is a node that is the upstream end of more than one segment; *cut off* means a segment's downstream node drains only through segments the subset dropped.

| subset | splits per group | segments cut off per group |
|---|---|---|
| all segments | 41–1,023 | 0 |
| `blue_line_key = watershed_key` | **0 in all 14** | 7–472 |
| edge types 1100/1150/1300/1350 dropped | 18–475 | 30–1,513 |

- **FWA already marks the tree.** Main flow (`blue_line_key = watershed_key`) has no splits in any of the 14 groups.
- **What it loses is tributaries whose mouth is on a side channel.** In KLUM, 234 cut-off mouths drain into edge types 1100 (147), 1350 (79), 1300 (5) and 1150 (3). Example: tributary `360883243` enters Skeena side channel `360222215` (edge type 1350), which joins the Skeena through a 1450 connector at measure 0.
- **Edge type 1450 is not secondary flow.** Hand-built networks that dropped 1450 along with the secondary types had to add the connectors back one by one; 24 of 26 such connectors in one project are main flow.

Method, per watershed group (nodes snapped to 1 cm):

```sql
with s as (
  select linear_feature_id id, (blue_line_key = watershed_key) mainflow, edge_type,
    st_snaptogrid(st_startpoint(st_force2d(geom)), 0.01) dn,
    st_snaptogrid(st_endpoint(st_force2d(geom)), 0.01) up
  from whse_basemapping.fwa_stream_networks_sp
  where watershed_group_code = :'wsg' and edge_type <> 1425
)
-- splits: nodes that are the `up` of more than one segment in the subset
-- cut off: subset segments whose `dn` is no subset segment's `up`, but is some full-network segment's `up`
```

Branch off `newgraph`; PR targets `newgraph`.

## Context from exploration

SSN2/SSNbler models need a dendritic network. FWA braids, so each project has been building its tree by hand, with segment picks keyed on measures that drift between FWA releases. The issue proposes a rule: keep main flow (`blue_line_key = watershed_key`), and reattach a tributary whose mouth is on a side channel by keeping that side channel from the entry point down, recursively. Its acceptance test is that the rule reproduces the two hand-built networks (Skeena, Nechako).

**What exploration found** (local `fresh-db`, db `fwapg`):
- The PCIC job's blue-line parents (`extras/pcic_crosswalk/sql/pcic_crosswalk01_paths.sql`, still staged as `fwapg.pcic_blk_parents`) already contain the reattachment routes. All four rows of the issue's table match: 360883243→360222215 @297.7, 360881231→360237491 @325.3, 360222215→360222216 @1386.5, 360884603→360216952 @1017.0. The nesting 360216952→360216962 is there too.
- **Prototype on all 14 issue groups** (main flow, plus side-channel segments below the highest junction a main-flow line routes through; 1425 excluded so the numbers compare with the issue's): **0 splits in all 14**. 2 segments are cut off in total, compared with 7–472 per group for main flow alone. Both are FWA geometry gaps where a parent junction does not touch the line: a `side_fallback` with a 401 m gap (LSKE) and a `code_deferred` with a 258 m gap (UNRS).
- Province-wide, 386 `code`, 37 `code_deferred` and 2,250 `side_fallback` junctions have a gap over 1 m. Those are where cut-offs can come from.
- Main-flow segments include all 343 of the edge type 1425 segments and 248 of the 250 edge type 6010 segments. The tree keeps both, because they carry connectivity.
- SSNbler/SSN2 are not installed. The hand-built model repos (`skeena-stream-temp-25`, `fish-passage-22b`) are not cloned locally.

**Decisions taken at the gate:** the parents move to a shared job used by both PCIC and the tree. The tree is exposed as a lookup table, built by an extras job and cached to `s3://fresh-bc/fwapg/`.

Branch off `newgraph` (not main); PR `--base newgraph`; `gh -R NewGraphEnvironment/fwapg`.

## Phase 1: Shared blue-line paths
- [x] `git mv` `extras/pcic_crosswalk/sql/pcic_crosswalk01_paths.sql` → `extras/blue_line_paths/sql/blue_line_paths.sql`. Rename the tables to `fwapg.blk_parents` / `fwapg.blk_paths` and the function to `fwapg.blk_on_or_upstream`, and make the header neutral (not PCIC-specific)
- [x] `extras/blue_line_paths/blue_line_paths.sh` (runs the SQL, then the cycle check already in it) and a `README.md` (junction rules, runtime 4–6 min, table layout)
- [x] PCIC job calls the shared script; rename the references in `pcic_crosswalk03`–`07`, `qa.sql`, `pcic_crosswalk.sh` cleanup (the shared tables persist; PCIC stops dropping them), and the README step 3 text
- [x] Verify there is no behaviour change. Snapshot the current `whse_basemapping.pcic_fwa_crosswalk` and `fwa_stream_networks_discharge_monthly` first, rerun the PCIC job from its `data/` cache, then compare: identical placements, |Δq| ≈ 0, QA 10/10
- [x] Update the path references in `research/fwa_position_codes.md`

## Phase 2: Tree job (tests first)
- [x] `extras/mainflow_tree/sql/qa.sql` (`name|bool`, PCIC's pattern), written before the build so it fails first. Tests:
  - no splits province-wide (a node that is the upstream end of more than 1 tree segment, nodes snapped to 1 cm)
  - cut-offs at or below a measured ceiling (a tree segment whose downstream node is an upstream node in the full network but not in the tree)
  - all 26 listed 1450 connectors are in the tree at measure 0
  - for each of the 4 tributaries, the side channel is kept from 0 to the entry measure and dropped above it
  - the Chilako (`100.567134.069486`) reaches the Nechako (`100.567134`) through tree segments
- [x] `extras/mainflow_tree/sql/mainflow_tree.sql`: main flow (codes not null and not `999`, all edge types) plus side-channel extents. The extents come from walking `fwapg.blk_parents` from every main-flow line through side channels until a main-flow line is reached; on each side channel the tree keeps the segments with `downstream_route_measure` < the maximum junction measure. Output `whse_basemapping.fwa_stream_networks_mainflow_tree (linear_feature_id PK, watershed_group_code, blue_line_key, reattached boolean)`
- [x] `extras/mainflow_tree/mainflow_tree.sh`: shared paths → build → `data/qa_cutoffs.csv` → QA (stop on failure) → export `.csv.gz`
- [x] Run it province-wide and record the splits and cut-offs by cause. Add `overrides.csv` (`linear_feature_id`, include/exclude, note) **only if** there are splits the rule gets wrong; cut-offs at FWA gaps are listed, not overridden

## Phase 3: SSNbler acceptance
- [x] Install `SSNbler` from CRAN (a machine change: one R package)
- [x] `extras/mainflow_tree/ssnbler_check.R`: read the tree subsets for the Skeena (`wscode <@ 400`, 9 groups) and the Nechako (`wscode <@ 100.567134`, 12 groups), reverse every line, then `lines_to_lsn(check_topology = TRUE)`. Report node errors and outlets. The test subset is the whole basin, which is stricter than the issue's "subset that connects the sites", because the site lists live in repos that are not cloned here
- [x] Record the results in findings

## Phase 4: Docs
- [x] `extras/mainflow_tree/README.md`: method, table, how to query (join on `linear_feature_id`), caveats (cut-offs at FWA gaps; watershed area on reattached segments is fwapg#4)
- [x] `extras/README.md`: the fresh-bc upload line
- [x] `research/fwa_mainflow_tree.md` (verdict, with the provenance line) and a row in `research/README.md`

## Validation

- [x] Tests pass (`qa.sql` all true; PCIC QA unchanged)
- [x] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [x] PWF checkboxes match landed work
- [x] `/planning-archive` on completion
