## Main-flow tree

A dendritic subset of `fwa_stream_networks_sp`, for models that need a stream network with no splits:
SSN2/SSNbler (spatial stream network models, e.g. stream temperature), additive function values, flow
accumulation. Before it, each project built its tree by hand, keyed on `blue_line_key` and floating-point
measures that stop matching after an FWA re-release (NewGraphEnvironment/fwapg#2).

FWA is not a tree: braids and side channels are mapped as secondary flow, so the network splits going
downstream. Main flow (`blue_line_key = watershed_key`) does not split, but on its own it cuts off every
tributary whose mouth is on a side channel. Dropping the secondary-flow edge types instead both leaves
splits and cuts tributaries off.


## Rule

1. **Main flow**: every segment of every blue line with `blue_line_key = watershed_key`, all edge types,
   including subsurface flow (1425), group connectors (6010) and connections (1450). Watershed codes under
   `999` (off the network) are left out.
2. **Reattachment**: a main-flow line whose mouth is on a side channel drains through that side channel. The
   tree keeps the side channel from the point where the water enters it down to its mouth, and recurses where
   a side channel drains into another side channel, until the water reaches main flow. The part of a side
   channel above its highest entry stays out, so no split is introduced. A line whose mouth is already on a
   main-flow node is not reattached: its water joins main flow there.
3. **Following**: a tree segment whose water continues only through dropped segments (a cut-off) is extended
   down the network while there is exactly one way down. This reaches the tree where a line's junction in the
   blue line paths is not where its mouth is (a code junction or side-channel fallback more than 1 m away).
4. **Overrides** (`overrides.csv`, `linear_feature_id`, `exclude` or `include`, note): one exclusion, a
   split between the Beaver River's two main lines (one watershed code, two `watershed_key` lines).

Which side channels a line drains through, and where it enters each, comes from the blue line downstream
paths (`extras/blue_line_paths`), the same paths the PCIC crosswalk uses.

FWA digitizes side channels like main flow, from the downstream end (measure 0), so a tree subset reversed
as a whole is digitized in the direction of flow, with no per-segment exceptions.


## Processing

    ./mainflow_tree.sh

Rebuilds the blue line paths (about 35 min), builds the tree (about 1 min), finds splits and cut-offs from the network geometry
(`sql/qa_topology.sql`, written to `data/qa_topology.csv` and kept as `fwapg.mainflow_tree_qa`), runs the
tests in `sql/qa.sql` (stopping before export if any fails) and writes `fwa_stream_networks_mainflow_tree.csv.gz`.

A *split* is a node that is the upstream end of more than one tree segment. A *cut-off* is a tree segment
whose downstream end is no tree segment's upstream end, but is some network segment's: its water continues
only through segments the tree dropped.


## Output

    Table "whse_basemapping.fwa_stream_networks_mainflow_tree"
            Column        |  Type   |
    ----------------------+---------+-------------------------------------------
     linear_feature_id    | bigint  | primary key, joins fwa_stream_networks_sp
     watershed_group_code | text    |
     blue_line_key        | integer |
     source               | text    | mainflow, reattached, followed, override

To get the tree's geometry:

    SELECT s.*
    FROM whse_basemapping.fwa_stream_networks_sp s
    INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t
      ON t.linear_feature_id = s.linear_feature_id
    WHERE s.watershed_group_code = 'KLUM';


## Results

In the 2026-10 build (4,907,441 network segments):

| | segments |
|---|---|
| main flow | 4,451,744 |
| reattached (19,745 side channels, 11,491 km) | 58,447 |
| followed (110 lines) | 177 |
| excluded by override | 1 |
| **tree** | **4,510,368** |

- **Splits: 0** province-wide. The network has 74,426 nodes where water leaves by more than one segment.
- **Cut-offs: 8**, against 28,870 for main flow alone. 28,824 main-flow lines drain through a side channel.
  Each of the 8 is a reattached side channel whose downstream node has two ways down, which following does not
  choose between (BARR, GOLD, KITR, KUSR, LFRA, MESI, OWIK, TATR; listed in `data/qa_topology.csv`).
- Reattachment alone (no main-flow-node rule, no following, no override) gave 7 split nodes and 97 cut-offs.
  6 of the splits were tributaries whose mouth is on a main-flow node, given as parent a side channel 0.7-1 m
  away near its top; the 7th is the Beaver River. Of the cut-offs, 65 were junctions more than 1 m from the
  mouth (33 deferred code junctions, 32 side-channel fallbacks), 21 touch junctions within 1 m, 11 lines with
  no parent.

## SSNbler check

`ssnbler_check.R` builds a landscape network from a tree subset with `SSNbler::lines_to_lsn(check_topology =
TRUE)`, reversing every line, and fails on any node error or more than one outlet:

    ogr2ogr -f GPKG data/skeena.gpkg PG:"$DATABASE_URL" -nln streams -sql \
      "SELECT s.linear_feature_id, s.geom FROM whse_basemapping.fwa_stream_networks_sp s
       INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t ON t.linear_feature_id = s.linear_feature_id
       WHERE s.wscode_ltree <@ '400'"
    Rscript ssnbler_check.R data/skeena.gpkg data/lsn_skeena

SSNBLER

## Caveats

- The 8 cut-offs are not repaired: the segments above each form a drainage with its own outlet.
- Following is geometric, so it can take a route the blue line paths would not (a side channel of a
  neighbouring tributary). It runs only where there is one way down.
- Watershed area on reattached side-channel segments is not handled here (NewGraphEnvironment/fwapg#4).
