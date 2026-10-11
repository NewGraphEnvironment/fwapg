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

Rebuilds the blue line paths (not while `pcic_crosswalk.sh` is running, see `extras/blue_line_paths`), builds the
tree, finds splits, cut-offs, dead ends and outlets with no parent inside BC from the network geometry
(`sql/qa_topology.sql`, written to `data/qa_topology.csv` and kept as `fwapg.mainflow_tree_qa`), runs the tests in
`sql/qa.sql` (stopping before export if any fails) and writes `fwa_stream_networks_mainflow_tree.csv.gz`. The whole
job took 20 min (2026-10-10, local Docker database on a 128 GB machine): paths 16 min, tree 3 min, topology QA
1.5 min. The QA took about 35 min while it unioned BC's boundary pieces around each mouth; it now builds BC's
outline once.

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
argument when one is given:

    ogr2ogr -f GPKG data/klum.gpkg PG:"$DATABASE_URL" -nln streams -sql \
      "SELECT s.linear_feature_id, s.geom FROM whse_basemapping.fwa_stream_networks_sp s
       INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t ON t.linear_feature_id = s.linear_feature_id
       WHERE s.wscode_ltree <@ '400' AND s.watershed_group_code = 'KLUM'"
    Rscript ssnbler_check.R data/klum.gpkg data/lsn_klum 1

`ssnbler_check.sh` does both, one run at a time, and kills the run when R and its workers together hold more
than a cap (in GB):

    ./ssnbler_check.sh 60 klum 400 KLUM 1      # <cap_gb> <name> <wscode> [group|-] [expected outlets]

It writes `data/ssnbler/klum.gpkg`, `data/ssnbler/lsn_klum` and `data/ssnbler/klum.log`, appends a line
with the exit status, R's own status, peak memory, minutes, lines and result to `data/ssnbler/runs.log`. It
exits 0 when clean, 1 on node errors or an unexpected outlet count, 2 on bad arguments or when another run
holds the lock, 3 when killed at the cap or by low system memory, 4 when memory could not be sampled, 5 when
there is no result for any other reason (the export failed, the subset is empty, R failed or was killed from
outside), and 129, 130 or 143 when the script itself is sent HUP, INT or TERM.

SSNbler (1.1.2) takes one of two paths, and they differ:

- **Below 46,340 lines it runs serially**, and memory grows with the square of the line count: 28 GB at
  21,700 lines, 52-54 GB at 29,000-30,000 (footprint, 2026-10-10). Check a large basin a watershed group at a
  time, and never two at once (three at once crashed a 64 GB machine).
- **At 46,340 lines or more it must run in parallel**, in chunks of 500 nodes, and memory grows about linearly:
  3.5 GB at 52,000 lines, 7.5 GB at 106,000, 16 GB for the Nechako (210,000 lines, 23 min), 20 GB for the
  Skeena (262,000, 35 min). But its unsnapped-node test is computed within each chunk, so an "Unsnapped Node"
  from this path is not reliable: on the same MSKE lines the serial path reports 4 errors and the parallel
  path 2, and the whole Skeena reports two unsnapped nodes in ZYMO that are exact nodes with no other line end
  within 2 m (the ZYMO group alone is clean on both paths). Its other node errors and outlet counts agree with
  the group runs.

In the 2026-10 build, every watershed group holding the Skeena (`400`) or the Nechako (`100.567134`), each
group's share of the basin checked on its own on the serial path:

- **27 of 29 groups: 0 node errors**, including KLUM, which holds three of the four side channels in the
  tests, and LSKE (29,000 lines), which holds the fourth (360216952). Each group has 1-3 outlets: where the
  basin leaves it (by two streams in 13 groups), plus any dead ends and `no_parent` outlets.
- **USKE and MSKE: 4 errors each, at one spot each**, a main-flow segment a few cm long whose geometry is a
  plain chain (239055049, 1.6 cm; 141013301, 2.9 cm). SSNbler reports its two ends as an unsnapped node and
  a divergence; the SQL check, on the same nodes at 1 cm, finds no split. At `snap_tolerance` 0.01 the two
  ends round to one node instead (SSNbler rounds nodes to one decimal place fewer than the tolerance).
- Not checkable: the Skeena's share of SPAT and TAKL and the Nechako's of TABR are one segment each, which
  `lines_to_lsn` cannot build (an error inside its own `left_join`).
- Whole basins, on the parallel path: the Nechako has **0 node errors and 8 outlets**, its mouth on the Fraser,
  6 dead ends (side channels reached by a fallback junction in FRAN, LEUT, LTRE (2), STUR and TAKL) and a
  `no_parent` side channel (UEUT), the same 8 counted in SQL. The Skeena has **1 outlet** (its mouth) and the
  two cm segments' divergences, plus the two ZYMO unsnapped nodes above.

## Caveats

- The 8 cut-offs, 473 dead ends and 23 outlets with no parent inside BC are not repaired: the segments above each form a drainage with its own
  outlet. A model subset that needs one outlet has to leave them out or close the gap itself.
- Following is geometric, so it can take a route the blue line paths would not (a side channel of a
  neighbouring tributary). It runs only where there is one way down.
- Watershed area on reattached side-channel segments is not handled here (NewGraphEnvironment/fwapg#4).
