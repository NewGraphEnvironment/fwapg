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

Rebuilds the blue line paths (about 35 min; not while `pcic_crosswalk.sh` is running, see
`extras/blue_line_paths`), builds the tree (about 1 min), finds splits, cut-offs, dead ends and outlets with no parent inside BC from the
network geometry (about 35 min, nearly all of it testing whether each mouth with no parent is at BC's edge)
(and dead ends; `sql/qa_topology.sql`, written to `data/qa_topology.csv` and kept as `fwapg.mainflow_tree_qa`), runs the
tests in `sql/qa.sql` (stopping before export if any fails) and writes `fwa_stream_networks_mainflow_tree.csv.gz`.

A *split* is a node that is the upstream end of more than one tree segment. A *cut-off* is a tree segment
whose downstream end is no tree segment's upstream end, but is some network segment's: its water continues
only through segments the tree dropped. A *dead end* is a tree segment whose downstream end is no network
segment's upstream end, on a line the blue line paths give a parent: the water continues, the geometry does
not.


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
  Each of the 8 is a segment added by following whose downstream node has two ways down, which following does
  not choose between (BARR, GOLD, KITR, KUSR, LFRA, MESI, OWIK, TATR; listed in `data/qa_topology.csv`).
- **Dead ends: 473**, all gaps in the geometry that no choice of segments closes: 354 main stems whose mouth
  is off their code junction (more than 1 cm), 119 side channels reached by a fallback junction (their mouth
  touches nothing). Each adds an outlet to any subset that contains it.
- **Outlets with no parent.** 26,713 tree mouths touch nothing, on lines the paths give no parent. 26,690 lie
  within 50 m of BC's edge (the coast or a land border: 26,686 main-flow lines, 4 side channels) and are
  outlets. 23 lie inside BC (`no_parent`): 11 main-flow lines and 12 reattached side channels, each a gap in the
  paths or a closed basin (for example SLOC 380887813, 15 m from the Slocan River; UEUT 355995011 in the
  Nechako).
- Every tree segment whose downstream end continues nowhere in the tree is one of these: 8 cut-offs, 473 dead
  ends, 26,690 outlets at BC's edge, 23 `no_parent`.
- Reattachment alone (no main-flow-node rule, no following, no override) gave 7 split nodes and 97 cut-offs.
  6 of the splits were tributaries whose mouth is on a main-flow node, given as parent a side channel 0.7-1 m
  away near its top; the 7th is the Beaver River. Of the cut-offs, 65 were junctions more than 1 m from the
  mouth (33 deferred code junctions, 32 side-channel fallbacks), 21 touch junctions within 1 m, 11 lines with
  no parent.

## SSNbler check

`ssnbler_check.R` builds a landscape network from a tree subset with `SSNbler::lines_to_lsn(check_topology =
TRUE)`, reversing every line. It fails on any node error, and on an outlet count other than the third
argument when one is given. SSNbler needs its parallel path (about 2 GB per worker) at 46,340 lines or more, so
check large basins a watershed group at a time:

    ogr2ogr -f GPKG data/klum.gpkg PG:"$DATABASE_URL" -nln streams -sql \
      "SELECT s.linear_feature_id, s.geom FROM whse_basemapping.fwa_stream_networks_sp s
       INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t ON t.linear_feature_id = s.linear_feature_id
       WHERE s.wscode_ltree <@ '400' AND s.watershed_group_code = 'KLUM'"
    Rscript ssnbler_check.R data/klum.gpkg data/lsn_klum 1

In the 2026-10 build, every watershed group holding the Skeena (`400`) or the Nechako (`100.567134`), each
group's share of the basin checked on its own (one at a time: peak memory grew from 1.5 GB at 5,500 lines to
39 GB at 24,000):

- **24 of 26 groups: 0 node errors**, including KLUM, which holds three of the four side channels in the
  tests. Each group has 1-3 outlets: where the basin leaves it (by two streams in 13 groups), plus any dead ends
  and `no_parent` outlets.
- The fourth, 360216952, is in LSKE (29,000 lines, too large): the tree within 5 km of it (783 lines) has 0
  node errors inside the window; the 5 reported, converging nodes at outlets, are each where the tree segment
  below lies outside the window.
- **USKE and MSKE: 4 errors each, at one spot each**, a main-flow segment a few cm long whose geometry is a
  plain chain (239055049, 1.6 cm; 141013301, 2.9 cm). SSNbler reports its two ends as an unsnapped node and
  a divergence; the SQL check, on the same nodes at 1 cm, finds no split. At `snap_tolerance` 0.01 the two
  ends round to one node instead (SSNbler rounds nodes to one decimal place fewer than the tolerance).
- Not run: LSKE, BULK and FRAN (29,000-30,000 lines, about 60 GB at that growth); the Skeena's share of SPAT and TAKL and
  the Nechako's of TABR are one segment each, which `lines_to_lsn` cannot build (an error inside its own `left_join`).
- Whole basins, counted in SQL with SSNbler's definition of an outlet: the Skeena has **1 outlet** (its
  mouth); the Nechako 8, its mouth on the Fraser, 6 dead ends (side channels reached by a fallback junction in FRAN,
  LEUT, LTRE (2), STUR and TAKL) and a `no_parent` side channel (UEUT).

## Caveats

- The 8 cut-offs, 473 dead ends and 23 outlets with no parent inside BC are not repaired: the segments above each form a drainage with its own
  outlet. A model subset that needs one outlet has to leave them out or close the gap itself.
- Following is geometric, so it can take a route the blue line paths would not (a side channel of a
  neighbouring tributary). It runs only where there is one way down.
- Watershed area on reattached side-channel segments is not handled here (NewGraphEnvironment/fwapg#4).
