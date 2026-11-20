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


## Upstream area

Each tree segment carries `upstream_area_ha`: the land whose water passes the segment's downstream end, routed
along the tree (NewGraphEnvironment/fwapg#4). Each fundamental watershed polygon is given to one tree segment and
the areas are summed down the tree, so area is additive at every confluence, which a spatial stream network
model's additive function assumes. The watershed lookup (`fwa_streams_watersheds_lut` with
`fwa_watersheds_upstream_area`) cannot give that on the tree: a side channel carries its river's watershed code,
so the lookup gives it the river's area (4 to 5 million ha on the Skeena's side channels, where the tributary
entering them has 51,420 to 302,611 ha).

Which segment a polygon goes to follows the lookup's own rule (`FWA_Upstream`, area at the polygon's outlet), so
plain main flow agrees with the lookup. In order:

1. `pair`: a polygon whose codes (watershed code and local code) are on main-flow segments goes to the top
   segment of that reach, and from there up its line to the highest segment in its range that lies in it. Its
   range: segments with no polygon of their own code, whose local code is above the polygon's and below the
   next that has a polygon.
2. `range`: a polygon whose codes are on no main-flow segment goes to the highest main-flow segment in its
   range that lies in it (on the line with the lowest `blue_line_key`, where two lines have one).
3. `pair_side`: failing that, a polygon whose codes are on reattached or followed segments, and that no
   main-flow segment of its own watershed code lies in, goes to the top one of them that lies in it (reattached
   before followed, then the lowest `blue_line_key`, where such segments are on several lines). Main flow of
   its own stream comes first because a polygon that holds both is the river's: one polygon had a 48 m
   side-channel segment and 18 km of main flow in it. Main flow of another stream in the polygon (a tributary
   crossing to the side channel) does not count.
4. `lower`: failing those, the top segment of the main-flow reach on its watershed code at the greatest local
   code at or below its own.
5. `ancestor`: failing that, on its nearest ancestor code in the tree, the top segment of the main-flow reach at
   the greatest local code strictly below the code of the branch it lies on.

**A segment lies in a polygon when its midpoint is inside it**, the test the lookup's own fallback uses. Codes
say where a polygon could be; they do not say where it is. A version of these rules that went by codes alone
put a polygon on a segment up its line that did not touch it for 6,368 of 23,897 polygons, on a side channel
that did not touch it for 5,470 of 8,431, and moved three cross-border polygons of 63,000 to 767,000 ha onto
the wrong lines. So a polygon leaves the place its codes give (rules 4 and 5, and the top of its own reach)
only for a segment that lies in it. Only rule 3 gives a polygon to a side channel, so a side channel carries
what enters it and the polygons that it, and not its river, lies in.

A polygon with no local code, or with one that is not under its own watershed code, is placed as if its local
code were its stream's mouth code (1,435 of the 1,457 such polygons end on a mouth-reach segment; 19 go up their
line by rule 1 and 3 are `ancestor`).
A polygon none of the rules places is listed in `fwapg.mainflow_tree_area_unassigned` with the reason: under
`999`; `no stream` (its watershed code and every ancestor of it are on no tree segment); or `below the tree`
(no main-flow reach is at or below it by its codes: it lies below its stream's lowest main-flow tree segment,
on a stream that leaves BC further down).

**Streams with no polygon of their own.** A segment with nothing above it after that lies in another stream's
polygon. It takes a share of the polygon at its midpoint, in proportion to its length against the length of all
tree segments in that polygon, taken from the segment the polygon was given to. The share is an estimate, kept
apart in `fwapg.mainflow_tree_area.shared_area_ha` and `fwapg.mainflow_tree_area_shares`.

**Gaps.** Area follows the tree's own nodes. At a cut-off or a dead end it is carried to the nearest tree
segment lower on the same blue line (`line`), or to the first line on the blue line path with a tree segment
below the junction (`junction`). Where the paths lead to no tree segment, the network ends and the segment is an
outlet.

`sql/qa_area.sql` compares the result with the lookup and gives every difference a class, in
`fwapg.mainflow_tree_area_qa` and `data/qa_area.csv`. The classes are found from routing, not from the areas:
each thing whose place in the tree is not the place its codes give (a line whose mouth is on a side channel, at
an outlet, across a gap or somewhere else than its code says; a polygon on a side channel; a length share; a
polygon with a bad local code) is counted for every segment it passes going down the tree, and for every segment
its codes put below it. The two are compared as sets, kind by kind (each marker has a number of its own, and the
sums are exact). A segment whose sets differ in a kind has that kind as its class; a main-flow segment whose sets
are equal is expected to agree with the lookup, and the tests hold the exceptions at the measured count.


## Processing

    ./mainflow_tree.sh

Rebuilds the blue line paths (not while `pcic_crosswalk.sh` is running, see `extras/blue_line_paths`), builds the
tree, finds splits, cut-offs, dead ends and outlets with no parent inside BC from the network geometry
(`sql/qa_topology.sql`, written to `data/qa_topology.csv` and kept as `fwapg.mainflow_tree_qa`), builds the
upstream area (`sql/mainflow_tree_area.sql`), compares it with the watershed lookup (`sql/qa_area.sql`, written to
`data/qa_area.csv`), runs the tests in
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
     upstream_area_ha     | double  | area draining through the segment's downstream end, ha

Kept beside it for review and for the tests:

| table | holds |
|---|---|
| `fwapg.mainflow_tree_area` | per segment: `downstream_id` and `downstream_method` (`node`, `line`, `junction`; NULL at an outlet), `depth`, `local_area_ha`, `shared_area_ha`, `upstream_area_ha`. `downstream_id` is the build's own working pointer, not a general downstream walk. |
| `fwapg.mainflow_tree_area_polygons` | per polygon: the segment it was given to, the rule (`method`), its area, and what went out of it as length shares |
| `fwapg.mainflow_tree_area_unassigned` | the polygons no rule places, with a class |
| `fwapg.mainflow_tree_area_shares` | per segment given a length share: the polygon and the share |
| `fwapg.mainflow_tree_area_qa` | every tree segment whose area differs from the lookup's or that has no lookup row, with a class |

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

### Upstream area

In the 2026-11 build (the 2026-10 tree; 3,245,453 watershed polygons):

| polygons | | area (ha) |
|---|---|---|
| `pair` (15,867 of them, 3,547,842 ha, moved up their line to a segment that lies in them) | 3,181,977 | 93,747,827 |
| `range` | 12 | 164,282 |
| `pair_side` | 1,820 | 95,860 |
| `lower` | 8,336 | 16,132,566 |
| `ancestor` | 20 | 2,128 |
| unassigned, no stream of their code or an ancestor code in the tree | 53,208 | 838,859 |
| unassigned, under `999` | 60 | 3,623 |
| unassigned, below the lowest main-flow tree segment of their stream | 20 | 351 |

- **Every tree segment has a positive area**, and area is additive at every node: a segment's area is its own
  polygons plus what flows in. The areas at the tree's 27,097 outlets sum to the area assigned, 110,143,331 ha.
  Every sum is taken in a fixed order, so two builds of the same inputs give the same area to the last bit.
- **Steps down the tree:** 4,483,174 by node, 93 by junction (90 dead ends and 3 cut-offs) and 4 by line
  (cut-offs). The other 383 dead ends and 1 cut-off have no tree segment below them on any line of their path
  and are outlets, with the 23 mouths with no parent and the 26,690 at BC's edge.
- **The test side channels carry what enters them.** 360216952 reads 53,007 ha below where tributary
  360884603 (51,420 ha) enters and 1,580 ha above it; 360222215 and 360222216 read 228,962 to 229,063 ha
  (tributary 360883243, 228,943 ha); 360237491 reads 302,611 to 302,813 ha (tributary 360881231, 302,611 ha).
  The lookup gives all of them 4.26 to 5.11 million ha. 360881231's mouth connector, which the lookup gives
  4,558,110 ha, reads 302,611.
- **Basins at their mouth:** Skeena 5,440,479 ha, Nechako 4,725,749 ha, Fraser 23,203,431 ha. The Skeena and
  the Nechako are within 0.01% of the polygons under their watershed code and the Fraser within 0.06%; the
  differences are streams a step across a gap brings in and dead ends inside the basin.
- **Length shares:** 1,898 segments, 181,075 ha out of 1,116 polygons (median share 14 ha; the largest is
  37,633 ha of a 42,667 ha polygon). 1,457 polygons (45,175 ha) have a local code that is not
  under their watershed code.
- **Against the lookup** (`sql/qa_area.sql`): of 4,362,376 main-flow segments whose lookup polygon has both
  their codes and whose local code is in order on their line, 4,288,277 have nothing upstream routed
  differently, and all but 293 of those agree with the lookup: 154 where the lookup's stored row is not what
  its own definition gives now, 138 segments whose local code is more than one level below their watershed
  code, and 1 not explained. Of the 74,099 with something routed differently, 73,808 differ. Every tree
  segment that differs or has no lookup row, 217,655 in all:

  | class | segments |
  |---|---|
  | reattached, followed (the lookup gives a side channel its river's area) | 58,624 |
  | the lookup's polygon is on the segment's stream at another local code | 53,591 |
  | the lookup's polygon is on another stream | 7,587 |
  | no lookup row | 2,353 |
  | routed differently: one kind (`side channel` 32,742, `bad code` 16,525, `share` 3,212, `edge` 2,926, `other place` 1,627, `outlet` 95, `side polygon` 5, `other stream` 4) | 57,136 |
  | routed differently: several kinds | 37,579 |
  | local codes out of order on the line | 492 |
  | lookup row not what its definition gives; segment code more than one level deep; not explained | 293 |

- The whole job took 47 min on 2026-11-20 (the same database, while another session was using it): the blue
  line paths, the tree and the topology QA about 35 min, the area build 5.5 min, the comparison with the lookup
  4.5 min, the tests and the export about 1 min.

## Article: the upstream area on the ground

`article/` holds a short article with an interactive map for each of seven cases of the upstream-area rules (a
test side channel, a polygon moved up its line, side-channel land against mapped floodplain, the Beaver River
cross-border polygon, a length share, a gap crossed and an outlet at BC's edge, and the main-flow difference the
QA leaves without a class), plus a chart of the confluence share, tree against lookup
(NewGraphEnvironment/fwapg#55). It renders from extracts committed beside it, with no database, and checks every
number it quotes against this README; the page stays local (gitignored):

    ./article/article_extract.sh     # needs DATABASE_URL; rewrites article/extracts/
    ./article/article_render.sh      # writes article/mainflow_tree_area.html

The maps need gq's `esri_satellite` basemap (NewGraphEnvironment/gq#123); the render script says how to install
it if it is missing.


## SSNbler check

SSNbler 1.1.2 on CRAN reports false node errors on FWA data (below). Install the fix from the
NewGraphEnvironment fork, pinned:

    Rscript -e 'pak::pak("NewGraphEnvironment/SSNbler@37ca338")'

`ssnbler_check.R` builds a landscape network from a tree subset with `SSNbler::lines_to_lsn(check_topology =
TRUE)`, reversing every line. It prints the SSNbler build it ran, and fails on any node error, on edge
relationships that split (an edge flowing into two) or do not number one per edge less the outlets, and on
an outlet count other than the third argument when one is given:

    ogr2ogr -f GPKG data/klum.gpkg PG:"$DATABASE_URL" -nln streams -sql \
      "SELECT s.linear_feature_id, s.geom FROM whse_basemapping.fwa_stream_networks_sp s
       INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t ON t.linear_feature_id = s.linear_feature_id
       WHERE s.wscode_ltree <@ '400' AND s.watershed_group_code = 'KLUM'"
    Rscript ssnbler_check.R data/klum.gpkg data/lsn_klum 1

`ssnbler_check.sh` does both, one run at a time, and kills the run when R and its workers together hold more
than a cap (in GB):

    ./ssnbler_check.sh 60 klum 400 KLUM 1      # <cap_gb> <name> <wscode> [group|-] [expected outlets]

It writes `data/ssnbler/klum.gpkg`, `data/ssnbler/lsn_klum` and `data/ssnbler/klum.log`, appends a line
with the exit status, R's own status, peak memory, minutes, lines, result and SSNbler build to
`data/ssnbler/runs.log`. It exits 0 when clean, 1 on node errors, bad edge relationships or an unexpected
outlet count, 2 on bad arguments or when another run
holds the lock, 3 when killed at the cap or by low system memory, 4 when memory could not be sampled, 5 when
there is no result for any other reason (the export failed, the subset is empty, R failed or was killed from
outside), 6 when the topology is clean and the area step failed, and 129, 130 or 143 when the script itself is sent HUP, INT or TERM.

**Additive function values from the tree's area.** With `SSNBLER_AREA=1` the export carries
`upstream_area_ha`, and after a clean topology check the script computes additive function values from it with
no overrides: `afv_edges(infl_col = "upstream_area_ha")`, then `sites_to_lsn` and `afv_sites` on the midpoints
of up to 200 edges. It prints one `area:` line, which `runs.log` carries too, and the run exits 6 when the
step fails: an edge with no area above zero, an additive function value outside (0, 1] or different from the
same value worked out by plain arithmetic (an edge's share of the edges flowing into the same edge, multiplied
down to the outlet), an outlet edge whose value is not 1, or a test side channel that takes more than 0.2 of its
confluence. That last check runs only where the subset holds a segment where 360216952 (through 360216962),
360222216 or 360237491 meets the Skeena; the `area:` line says how many it held.

    SSNBLER_AREA=1 ./ssnbler_check.sh 40 klum_area 400 KLUM 1

Any positive areas give values in (0, 1] and 1 at the outlets, so two of the checks are the ones that can
tell a wrong result. The equality with plain arithmetic holds SSNbler's value on every edge to what the areas
say. And where a side channel meets its river, its segment proportional influence is the tributary's area over
the river's: with the watershed lookup's area on KLUM's network the two side channels there take 0.5 of their
confluence, with the tree's 0.048 and 0.066. `sql/qa.sql` measures the same share in SQL at all 16,745 places a
side channel flows into main flow: a median of 0.5% with the tree's area (15,864 under a fifth), 50% with the
lookup's.

Four subsets, 2026-11-20, the fork at 37ca338, each with 0 node errors, no overrides, 200 sites, and values
equal to plain arithmetic on every edge:

| subset | lines | minutes | peak GB | outlets | values | covers |
|---|---|---|---|---|---|---|
| tributary 360884603's basin (`400.107640`) | 3,190 | under 1 | 0.6 | 1 | 2.4e-05 to 1 | the smallest case |
| KLUM (`400`, group KLUM) | 24,732 | 8 | 28.0 | 1 | 1.3e-07 to 1 | side channels, one flowing into another; 360222216 and 360237491 meet the Skeena here |
| the Bulkley (`400.431358`) | 52,293 | 21 | 2.8 | 1 | 1.9e-07 to 1 | SSNbler's parallel path |
| LTRE (`100.567134`, group LTRE) | 8,484 | 1 | 3.1 | 3 | 5.4e-07 to 1 | two dead ends: three outlets to SSNbler, and the area carried across both gaps |

Not run: LSKE, which holds the place 360216952's water meets the Skeena (about 29,000 lines on the serial path,
more memory than the machine these ran on had free); its share there is 0.0104 in SQL. And the whole Skeena:
`afv_edges` finds each edge's path to the outlet and tests every edge against it, so its time grows with the
square of the edge count (about 3.5 min at 24,732 edges), which is hours at 262,000. The plain arithmetic in
`ssnbler_check.R` gives the same values in one pass.

SSNbler takes one of two paths, and they differ:

- **Below 46,340 lines it runs serially**, and memory grows with the square of the line count: on 1.1.2,
  28 GB at 21,700 lines, 52-54 GB at 29,000-30,000 (footprint, 2026-10-10); on the fork, 17-18 GB at 21,700
  and 24-28 GB at 24,700 (2026-10-11). Check a large basin a watershed group at a time, and never two at once
  (three at once crashed a 64 GB machine).
- **At 46,340 lines or more it must run in parallel**, in chunks of up to 500 nodes, and memory grows about
  linearly: on 1.1.2, 3.5 GB at 52,000 lines, 7.5 GB at 106,000, 16 GB for the Nechako (210,000 lines,
  23 min), 20 GB for the Skeena (262,000, 35 min); on the fork, 3.8 GB at 52,000 and 10.9 GB for the Skeena,
  which took 54 min (its distances are computed in R, pdist's in C).

Two SSNbler 1.1.2 defects produce false errors on FWA data (pet221/SSNbler#8; `ssnbler_reprex.R` reproduces
both with synthetic lines, and is clean on the fork):

- **Precision.** SSNbler measured node distances with `pdist::pdist()`, which rounds coordinates to single
  precision, so at BC Albers coordinates points several cm apart can read as 0 apart. A segment a few cm
  long then reads as an unsnapped node and a divergence at each end, whatever `snap_tolerance` says, and its
  edge relationships are wrong.
- **Parallel path.** Its unsnapped flags are row numbers within a chunk, applied to the whole node list
  without the chunk's offset, so they land on the wrong nodes; a duplicate split across two chunks is
  missed.

The fork (`NewGraphEnvironment/SSNbler`, branch `fix-pdist-precision-parallel-unsnapped`) computes distances
in double precision and counts duplicates across chunks (NewGraphEnvironment/fwapg#16). A pull request with
these fixes (pet221/SSNbler#9) was closed on 2026-10-22: the maintainer asked to discuss in pet221/SSNbler#8
first, and has taken it on. The fork stays pinned here until an SSNbler release fixes the errors. Once distances are exact the second defect cannot fire, so no run here
exercises its fix; the fork tests it directly.

In the 2026-10 build, every watershed group holding the Skeena (`400`) or the Nechako (`100.567134`), each
group's share of the basin checked on its own on the serial path with SSNbler 1.1.2:

- **27 of 29 groups: 0 node errors**, including KLUM, which holds three of the four side channels in the
  tests, and LSKE (29,000 lines), which holds the fourth (360216952). Each group has 1-3 outlets: where the
  basin leaves it (by two streams in 13 groups), plus any dead ends and `no_parent` outlets.
- **USKE and MSKE: 4 errors each, at one spot each, all false.** Each is a main-flow segment a few cm long in
  a plain chain (239055049, 1.6 cm; 141013301, 2.9 cm), and the SQL check finds no split there. It is the
  precision defect. Shifted to small coordinates, the errors mostly go away but not entirely: an integer offset
  took USKE from 4 to 0 and MSKE to 1, a bounding-box corner MSKE to 0 and USKE to 1, consistent with `pdist`
  still being off by about 9 mm at 10⁵ m.
- Not checkable: the Skeena's share of SPAT and TAKL and the Nechako's of TABR are one segment each, which
  `lines_to_lsn` cannot build (an error inside its own `left_join`).
- Whole basins, on the parallel path: the Nechako has **0 node errors and 8 outlets**, its mouth on the Fraser,
  6 dead ends (side channels reached by a fallback junction in FRAN, LEUT, LTRE (2), STUR and TAKL) and a
  `no_parent` side channel (UEUT), the same 8 counted in SQL. The Skeena has **1 outlet** (its mouth) and 6
  false errors: the two cm segments' divergences, and two unsnapped nodes in ZYMO, which are MSKE's segment
  ends (rows 462 and 463 of their chunk) applied to rows 462 and 463 of the whole list. USKE's two ends fall
  in different chunks, so neither is flagged.

Re-run on the fork at 37ca338 (2026-10-10 and 11), the same exports:

- **USKE and MSKE: 0 node errors**, 1 outlet each, with 239055049 (1.6 cm) and 141013301 (2.9 cm) present.
- **The whole Skeena, parallel: 0 node errors and 1 outlet**, and 261,763 relationships for 261,764 lines,
  none flowing into two.
- The Bulkley (52,293 lines, parallel, clean on 1.1.2): `relationships.csv`, `noderelationships.csv` and
  `nodexy.csv` byte-identical to 1.1.2's.
- The Skeena and the Bulkley ran on a local build of the branch one wording-only rewrite before 37ca338
  (`runs.log` reads `local`); the R code is identical. USKE and MSKE ran on both, the second time installed
  from GitHub at 37ca338.

## Caveats

- The 8 cut-offs, 473 dead ends and 23 outlets with no parent inside BC are not repaired: the segments above each form a drainage with its own
  outlet. A model subset that needs one outlet has to leave them out or close the gap itself.
- Following is geometric, so it can take a route the blue line paths would not (a side channel of a
  neighbouring tributary). It runs only where there is one way down.
- Upstream area is the tree's: a segment below one of the 384 outlets inside BC where the network ends (383 dead
  ends and 1 cut-off, 179,631 ha above them, the largest 50,535 ha) does not carry the area above it, and neither
  does one below a mouth with no parent.
- 1,898 segments with no polygon at or above them carry a length share of the polygon they lie in
  (181,075 ha in all): an estimate, not a measured catchment.
- "Lies in" is a midpoint test. Land between a river and its side channels (bars, islands, floodplain) has
  codes that do not say which channel it drains to; here it stays with the river unless a side-channel segment's
  midpoint is inside the polygon and no main-flow segment of the polygon's own stream is
  (NewGraphEnvironment/fwapg#53).
- 53,208 polygons (838,859 ha) belong to no tree segment: their watershed code is on no stream of the network
  and has no ancestor in the tree (land that drains to the sea or out of BC with no mapped stream). 20 more
  (351 ha) lie below the lowest main-flow tree segment of their stream.
- 1 main-flow segment differs from the lookup with nothing routed differently and no anomaly in its codes; it
  is not explained (`class IS NULL` in `fwapg.mainflow_tree_area_qa`).
