# Code-check round 4: review of the round-3 fixes (5892c98..708876d)

Scope: `git diff 5892c98..708876d` (qa_topology.sql, qa.sql, mainflow_tree README, blue_line_paths README,
ssnbler_check.R, research/fwa_mainflow_tree.md). Every number was re-derived read-only against fresh-db
(`fwapg`), with a GROUP BY on the attribute each sentence names. SSNbler was not run; its committed logs
were read.

## Claims

| claim | file:line | status | evidence |
|---|---|---|---|
| the 8 cut-offs are segments added by following | README:86-87, qa.sql:15-17, research:25 | VERIFIED | `mainflow_tree_qa` JOIN tree: cut_off / followed = 8 |
| each cut-off's downstream node has two ways down | same | VERIFIED | segments whose end point is within 5 mm of each cut-off's start: 2 in all 8; 0 of them in the tree |
| cut-off groups BARR GOLD KITR KUSR LFRA MESI OWIK TATR | README:87 | VERIFIED | DB |
| 16 side channels with no parent | README:91, qa.sql:31-35, research:25 | VERIFIED | `kind='no_parent'` = 16, all `source='reattached'`, all `blk <> watershed_key` |
| "whose mouth touches nothing" | README:91, qa_topology.sql:15, research:25 | VERIFIED | nearest other network line to each mouth 18.2-548.1 m; nothing within 1 m |
| each is its line's lowest segment (a mouth) | same | VERIFIED | all 16 at the min measure of their blue line (3 of them start above 0: KUSR 47,401.1, LSTR 900.9 and 206.4, cropped at the BC border) |
| "their own main stem more than 1 km away" | README:92, qa_topology.sql:16 | VERIFIED | min distance to the watershed_key line 1,042.1-23,049.9 m; 0 main-stem segments share the local code (so the code half of the fallback cannot fire either) |
| "the water's way on is unknown" | qa_topology.sql:16-17 | FALSE for 4 of 16 | KUSR 360214815, LSTR 360216270, LSTR 360216271, TATR 360232387 have their mouth on the BC border (about half of a 50 m buffer around each lies outside `fwa_bcboundary`): their water leaves BC, as the main-flow outlets' does. 12 are inland (ALBN 1.5 km and NBNK 3.3 km from the border, the rest 77-211 km). See F1 |
| UEUT in the Nechako | README:93 | VERIFIED | 355995011, wscode 100.567134.641477.593274; 100.567134 is the Nechako River |
| GRNL and LNIC under the Thompson (wscode 100.190442) | README:93 | VERIFIED | GRNL 355993798 on 100.190442.506118 (Bonaparte), LNIC 355994976 on 100.190442.244975 (Nicola); 100.190442 is the Thompson River |
| 26,697 other tree outlets, main-flow lines with no parent | README:93-94 | VERIFIED (count and class) | dangling tree segments with no parent: 26,697 all `source='mainflow'`, `blk = watershed_key`, line bottom |
| "water that leaves BC or ends at the sea or a closed basin" | README:94, qa_topology.sql:17-19 | FALSE for 1 (rest not fully checked) | of main-flow no-parent lines whose parent code has a main stem in BC (601), 594 are on the BC border, 6 touch the network (not outlets), 1 is a mid-basin outlet: SLOC 380887813 (one segment, 868144605), mouth 14.8 m from Slocan River segment 356368186 (edge 1350), 413 m from the Slocan main stem, 76 km from the border. The 26,095 whose parent code is absent from BC (plus 7 top-level codes) were not split by fate. See F2 |
| the 16 and 26,697 partition the no-parent outlets | README:91-94 | VERIFIED | all dangling tree segments = 27,186 = 354 + 110 + 9 (dead_end 473) + 16 (no_parent) + 26,697 (main flow, no parent); no row in two kinds |
| Nechako 8 outlets = mouth + 6 dead ends (FRAN, LEUT, LTRE x2, STUR, TAKL) + UEUT | README:130-131, research:25 | VERIFIED | basin subset (tree, wscode <@ 100.567134): TABR 356362759 (mouth, no QA kind); dead_end FRAN 355997056, LEUT 355997802, LTRE 355998334 and 355993377, STUR 356000352, TAKL 355996515; no_parent UEUT 355995011 |
| Skeena 1 outlet | README:129, research:25 | VERIFIED | LSKE 360887278 only |
| each group has 1-3 outlets | README:119 | VERIFIED | per-basin group subsets: 1-3 |
| leaves the group by two streams in 13 groups | README:119 | VERIFIED | CHES CHIL DRIR LCHL LEUT LNRS STUL STUR TAKL UEUT UNRS UTRE ZYMO, two distinct blue lines each, none a QA row; all 13 among the 26 run |
| "... and any dead ends" (the third outlet) | README:119 | FALSE for 1 group | UEUT's third outlet is the no_parent side channel, not a dead end (LEUT, LTRE, STUR, TAKL, FRAN's are dead ends). See F3 |
| KLUM holds three of the four test side channels | README:118-119 | VERIFIED | 360222215, 360222216, 360237491 in KLUM; 360216952 in LSKE |
| LSKE 29,000 lines, too large | README:120 | VERIFIED | 29,266 |
| tree within 5 km of 360216952 = 783 lines | README:120 | VERIFIED | `ST_DWithin(geom, collect(360216952), 5000)` over tree = 783, identical ids to `lske_360216952.csv` (783 unique) |
| 0 node errors inside the window; 5 reported, converging nodes at outlets, each where the tree segment below lies outside | README:120-122, research:33 | VERIFIED | log: node errors 5, all `Outlet / Converging Node`, outlets 17. At each of the 5 points (node_errors.gpkg): 2 window segments start there, 1 tree segment ends there, 0 window segments end there |
| junction_gap_m up to 1 m on a touch | paths README:46 | VERIFIED | touch max 0.9934 (18 > 0), touch_round max 0.9987 (34 > 0) |
| SSNbler rounds to one decimal fewer than snap_tolerance | ssnbler_check.R:34 | VERIFIED | `ndec <- get_decimals(snap_tolerance) - 1` in installed SSNbler |
| qa_topology joins ends in the same 1 cm cell rather than by distance | ssnbler_check.R:35-36 | VERIFIED | `round(x * 100)::bigint` equality |
| topo_tolerance 1 m and 1 cm gave the same errors | ssnbler_check.R:37 | VERIFIED (logs) / UNVERIFIABLE (parameter) | v2_ and v3_ USKE and MSKE logs identical (2 divergence + 2 unsnapped each); that v3 used 1 cm is recorded only in progress.md:27, no v3 script kept. Tested on those two groups only, so "here" is two groups |
| at 46,340 or more it requires its parallel path | research:33, README:105 | VERIFIED | `max.edges <- 46340; if (n_edges >= max.edges && (!use_parallel ...)) stop` |
| 24 of 26 groups 0 errors, and around the fourth test side channel | research:33 | VERIFIED | logs; LSKE window as above |
| provenance: SQL run step by step, scripts not run end to end | research:3 | accepted | per brief |

## Findings

- **[bug]** extras/mainflow_tree/sql/qa_topology.sql:15-17 — **F1.** The `no_parent` definition says "the water's
  way on is unknown", but 4 of the 16 (KUSR 360214815, LSTR 360216270 and 360216271, TATR 360232387) have their
  mouth on the BC border, and three of them start above measure 0 because the line is cropped there: their water
  leaves BC, which is the fate the same comment gives main-flow lines to justify not listing them. The kinds are
  split by main flow vs side channel, not by fate, so the comment's contrast is wrong in both directions (see F2).
  The README Caveats line (README:135-136, "the 16 side channels with no parent ... close the gap itself") inherits it: there is no
  gap in BC to close for those 4. Fix: say what the class is ("a side channel with no parent; 4 of the 16 leave BC,
  12 end inland") rather than give one fate to all.

- **[bug]** extras/mainflow_tree/README.md:93-94, sql/qa_topology.sql:17-19 — **F2.** "The other 26,697 tree
  outlets are main-flow lines with no parent: water that leaves BC or ends at the sea or a closed basin." One of
  them does not: SLOC 380887813 (segment 868144605), a one-segment main-flow line whose mouth is 14.8 m from the
  Slocan River (segment 356368186, edge 1350), 413 m from the Slocan main stem and 76 km from the border. Its water
  enters the Slocan; the paths give it no parent because no Slocan main-stem segment carries its local code and
  nothing is within 1 m. It is exactly the gap `no_parent` was added to catch, and the `NOT n.in_mainflow` filter
  makes it uncounted by every QA kind and every ceiling. Same mechanism as round 3: a measured count carrying an
  inferred label. Fix: either list main-flow lines with no parent whose parent code has a main stem in BC and whose
  mouth is not on the BC boundary (1 today), or state the exception. blue_line_paths README rule 6 ("leaves BC ...
  or it has no parent code in BC") is also not exhaustive for this line, which has a parent code in BC and does not
  leave BC.

- **[bug]** extras/mainflow_tree/README.md:119 — **F3.** "Each group has 1-3 outlets: where the basin leaves it
  (by two streams in 13 groups) and any dead ends." UEUT has 3 outlets: 2 exits and the no_parent side channel
  355995011, not a dead end. Fix: "and any dead ends or side channels with no parent".

- **[fragile]** extras/mainflow_tree/sql/qa_topology.sql:81 — `NOT n.in_mainflow` is a per-segment `source` test
  standing in for "side channel". `mainflow_tree.sql:35` allows `source = 'override'`: an override-included segment
  on a main-flow line that dangles with no parent would be reported as a no_parent "side channel", while a
  `reattached`/`followed` segment is never on a main-flow line today (0 such). Conversely the output column
  `mainflow` (`blk = watershed_key`) disagrees with `source` on 7 tree segments (SIML 356367095 x6, BEAV 359024601),
  so a reader filtering the CSV by `mainflow` and the test filtering by `source` can count different things. Today
  the 16 agree on both. Discriminating at the line (no `source='mainflow'` segment on the blue line) would match the
  README's "main-flow lines".

- **[fragile]** extras/mainflow_tree/README.md:42 — the Processing sentence edited in this diff lists "splits and
  cut-offs ... (and dead ends" but not side channels with no parent; qa_topology.sql:1 still says "Splits and
  cut-offs". Doc staleness only.

Not findings (checked):
- `no_parent` does not overlap `cut_off` (EXISTS vs NOT EXISTS a network segment ending at dn) or `dead_end`
  (EXISTS vs NOT EXISTS a parent), and with them and the main-flow exclusion it partitions all 27,186 dangling tree
  segments.
- On empty or broken input: a `count(*) <= 16` ceiling passes on zero rows (the accepted ceiling pattern). Emptying
  `blk_parents` would push no_parent to 126 and fail; an empty tree fails test 1. `source` has no NOT NULL
  constraint, but `NOT NULL` filtering only matters if a tree row had NULL source (0 today).
- `followed` segments are rightly included by `NOT in_mainflow`: they lie on side channels (177, all
  `blk <> watershed_key`); none has no parent today.
