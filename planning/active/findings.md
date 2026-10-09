# Findings — Main-flow tree: a dendritic stream network computed from FWA (#2)

## Issue context

**If we do it:** a model that needs a dendritic network (SSN2/SSNbler for stream temperature, any additive-function or flow-accumulation model) gets one from FWA with a query, the same way for every user. **If we never do:** each project rebuilds a tree by hand. Two recent stream-temperature projects did, with about 45 hard-coded segment picks keyed on `blue_line_key` and floating-point measures, which stop matching after an FWA re-release.

## Problem

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

## Proposed Solution

A main-flow tree, computed from FWA:

1. Main flow: `blue_line_key = watershed_key`.
2. Reattach each cut-off tributary by keeping the side-channel path from its mouth down to the main flow (the side channel's segments below the entry point, recursively where a side channel drains into another). The part of the side channel above the entry stays out, so no split is introduced.
3. Expose it as a flag on `fwa_stream_networks_sp` or as a view, plus a check that each watershed group's tree has one outlet per drainage and no splits.

Open: whether reattachment ever has more than one candidate path (a side channel that itself braids), and how to pick when it does. An override table keyed on `linear_feature_id` covers the cases a rule gets wrong.


## Flow direction

FWA digitizes side channels the same way as main flow: measure 0 is the downstream end. On the four side channels below, measure 0 is the low end, 1.3–1.8 m below the top. So a tree built from the rule above needs no per-segment direction exceptions. Lines reversed as a whole for SSNbler (which wants them digitized in the direction of flow) are all consistent.

A hand-built network needed four exceptions. They came from its routing, not from FWA. Two of its four reattachments followed the side channel *upstream* from the tributary's entry to where the channel leaves the river, so those segments ran against FWA's direction:

| tributary | enters side channel | at measure | rule keeps (downstream) | hand-built kept |
|---|---|---|---|---|
| 360883243 | 360222215 | 297.7 | 0–297.7 | 0–297.7 |
| 360881231 | 360237491 | 325.3 | 0–325.3 | 0–325.3 |
| 360222215 (its mouth) | 360222216 | 1386.5 | 0–1386.5 | **1386.5–1628 (upstream)** |
| 360884603 | 360216952 | 1017.0 | 0–1017.0 | **1017.0–3351 (upstream)** |

Side channels also nest: 360222215 drains into side channel 360222216, and 360216952's measure 0 meets side channel 360216962. Reattachment has to recurse until it reaches main flow.

## Acceptance

Two hand-built networks, made for SSN2 stream-temperature models before this rule existed, are the test. The rule has to reproduce them without their hand-made lists.

**Skeena (KLUM, LSKE, MSKE, KISP, BULK, MORR, BABL, BABR, ZYMO).**
- Every one of the 26 edge-type-1450 connectors the hand-built network added back is in the tree: `blue_line_key` 360883243, 360222215, 360237491, 360881231, 360884603, 360422693, 360879488, 360768563, 360397147, 360869584, 360873822, 360850339, 360885864, 360886970, 360678242, 360814623, 360816333, 360886207, 360885316, 360886221, 360882037, 360801822, 360887063, 360715518, 360884191, 360859802, each at measure 0. 24 are main flow already; 360222215 and 360237491 are side channels and come in through reattachment.
- Tributaries 360883243, 360881231, 360884603 and 360222215's mouth reach main flow through the downstream paths in the table above.
- SSNbler `lines_to_lsn(check_topology = TRUE)` on the tree subset that connects the sites reports no node errors and one outlet, with every line reversed and no exceptions.

**Nechako (NECR, CHES, LCHL, LNRS, UNRS, CHIL, FRAN, MIDR, LTRE, UTRE, STUR, STUL).** The Chilako (`wscode` 100.567134.069486) connects to the Nechako (100.567134). The hand-built network needed one side-channel path added back for this.

Watershed area on the reattached side-channel segments is #4. The tree is accepted on topology alone; area is checked there.

## Prototype (2026-10-09, local fresh-db)

Main flow plus side-channel segments below the highest junction a main-flow line routes through, using the staged
`fwapg.pcic_blk_parents`; edge 1425 excluded to compare with the issue's table.

| wsg | tree segments | side channels reattached | splits | cut off |
|---|---|---|---|---|
| KLUM | 25,344 | 161 | 0 | 0 |
| LSKE | 29,557 | 305 | 0 | 1 |
| MSKE | 25,306 | 100 | 0 | 0 |
| KISP | 24,070 | 60 | 0 | 0 |
| BULK | 31,557 | 111 | 0 | 0 |
| MORR | 23,516 | 110 | 0 | 0 |
| BABL | 25,230 | 16 | 0 | 0 |
| ZYMO | 19,317 | 99 | 0 | 0 |
| NECR | 22,458 | 30 | 0 | 0 |
| CHES | 8,206 | 6 | 0 | 0 |
| LCHL | 16,136 | 28 | 0 | 0 |
| UNRS | 25,194 | 35 | 0 | 1 |
| STUR | 11,853 | 17 | 0 | 0 |
| FRAN | 31,502 | 45 | 0 | 0 |

Both cut-offs are junctions that do not touch: LSKE side channel 360230470 (`side_fallback`, 401 m gap; its mouth
touches 360230472, a side channel of a deeper-coded tributary), UNRS main stem 356318856 (`code_deferred`, 258 m;
its mouth touches side channel 355995648, itself a `side_fallback` with a 929 m gap).

Province-wide junction gaps over 1 m: `code` 386 of 1,467,190; `code_deferred` 37 of 37; `side_fallback` 2,250 of 2,250.

## Phase 1 measurements (2026-10-09)

- Paths build 14:45:41 -> 15:20:58 UTC (35 min, incl. a ~1 min snapshot). A 2,634-line sample of the touches lateral took 3.2 s (1.2 ms/line), so ~33 min for 1.6M lines: the research note's "4-6 min" was wrong for this host.
- PCIC steps 02-07 + drainage + QA after the paths: 7 min.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| Python `str.index('-- 4. overrides')` matched the header comment, duplicating mainflow_tree.sql (`relation "net_nodes" already exists`) | anchor replacements on a unique string; check with grep -c |
| `ls grp_*.gpkg \| xargs` passed colour escape codes (ls is aliased to colourise), every SSNbler run failed on a missing file | `find -print` instead of `ls` in pipelines |
| SSNbler `in_edges contains 160582 edges, which is >= 46340. Set use_parallel = TRUE` | per watershed group, serial; parallel workers hold ~2 GB each |
| SSNbler `left_join()` error on a one-line network (TABR's single Nechako segment) | SSNbler edge case, reported not worked around |
| `psql $DATABASE_URL` unset / password prompt on localhost | `docker exec -i fresh-db psql -U postgres -d fwapg` |
