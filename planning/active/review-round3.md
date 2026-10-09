# Code-check round 3: claims enumeration (#2)

Reviewer run 2026-10-09 (~21:00 UTC). Read-only: SSNbler 1.1.2 source dumped from its namespace,
SELECT/TEMP queries on fresh-db, the SSNbler logs in `extras/mainflow_tree/data/ssnbler/`, and
`planning/active/*.md`. No repo script or SQL file was run; the repo tree was not edited (except this file).

## Mechanism

The hypothesis (statements about an external tool written from memory instead of its source) is half of it,
and it accounts for the minor items (F7, F8, I1). The bigger class here is narrower:

**A measured count carrying an inferred label.** Almost every number in this diff is correct: each one was
produced by a query, and re-running the query gives it again. What is wrong is the *qualifier attached to a
count*: "each of the 8 is a reattached side channel", "the other 26,697 are lines with no parent: the sea,
borders, closed basins", "8 outlets = mouth + 7 dead ends", "each group's outlets are its exit plus dead
ends", "KLUM holds the four side-channel paths". Each was written from the author's model of *why* the count
is what it is, and none was checked by grouping the same rows by the attribute the sentence names (source,
has-parent, kind, group). The count could be right while the explanation was wrong, and nothing would fail.
R2's defect (snap 0 -> 1 m) is the tool-semantics version of the same thing: the shape of a fact taken from
a paraphrase, not from the source.

The check that discriminates is cheap: for every sentence of the form "N things, each/all/the rest X",
`GROUP BY X` over the rows that produced N.

## Findings (FALSE claims and bugs)

**F1. The 8 cut-offs are not "reattached side channels".** README.md:86-87, sql/qa.sql:15-16,
research/fwa_mainflow_tree.md:25. All 8 cut-off segments have `source = 'followed'`. They are on 8
side-channel lines; only 3 of those lines (355993394, 360221119, 360226879) have any reattached segment; the
other 5 (354087807, 359004909, 360214844, 360222251, 360226346) are in the tree only through following. Each
does stop at a node with exactly two ways down (verified: 2 network segments start at each). LFRA 355993394
has no parent at all. Fix: "Each of the 8 is the last segment following added on a side channel, at a node
with two ways down, which following does not choose between."

**F2. "The 26,697 other tree outlets are lines with no parent: the sea, borders, closed basins" is wrong in
count and in kind, and the QA cannot see the difference.** README.md:90-91, sql/qa_topology.sql:14-15.
Tree outlets (tree segments whose downstream node is no tree segment's upstream node) = 27,194 = 8 cut-offs +
473 dead ends + **26,713** others. Of the 26,713: 26,697 are main-flow lines with no parent; **16 are
reattached side channels with no parent** in `blk_parents`. Reattachment walks parents up from main flow, so
a side channel with no parent is kept from its entry down to a mouth that goes nowhere. Some are mid-basin,
not sea/border/closed basin: UEUT 355995011 (`100.567134.641477.593274`, inside the Nechako), GRNL 355993798
and LNIC 355994976 (under the Thompson, `100.190442`); others (TATR 360232387 `990`, KUSR 360214815 `800`) may
be border cases. Because `dead_end` requires `EXISTS (blk_parents ...)`, these 16 are neither dead ends nor
cut-offs: no QA row, no ceiling, and the 473 regression guard does not cover them. Fix: give non-main-flow
tree outlets with no parent their own kind (or count them as dead ends), add a ceiling, and correct the two
sentences (26,713 = 26,697 main-flow lines + 16 side channels with no parent).

**F3. The Nechako's 8 outlets are its mouth, 6 dead ends and 1 side channel with no parent, not 7 dead
ends.** README.md:124-125, research/fwa_mainflow_tree.md:25 (and progress.md:17). The 8 (SQL, nodes at 1 cm,
SSNbler's outlet definition): TABR 356362759 (the mouth on the Fraser); dead ends FRAN 355997056, LEUT
355997802, LTRE 355993377, LTRE 355998334, STUR 356000352, TAKL 355996515 (all `side_fallback`); and UEUT
355995011, which has no parent (F2) and no QA kind. The count 8 is right, the composition is not, and UEUT
has no dead end at all. Fix: "its mouth on the Fraser, 6 dead ends (side channels reached by a fallback
junction in LEUT, TAKL, FRAN, LTRE (2) and STUR) and one side channel with no parent in UEUT (355995011)".

**F4. "Each group has 1-3 outlets: the point where the basin leaves the group, plus any dead ends."**
README.md:116. The counts 1-3 match the logs, the decomposition does not. Per-group outlets classified in
SQL (the SQL outlet counts equal SSNbler's in every group I compared): CHES, CHIL, DRIR, LCHL, LNRS, STUL,
UNRS, UTRE have 2 outlets and 0 dead ends (the basin leaves the group by two streams, e.g. CHES: 356163562 to
LNRS and the Nechako to NECR); LEUT, STUR, TAKL have 2 exits + 1 dead end; UEUT has 2 exits + the no-parent
side channel (F2), 0 dead ends; ZYMO has 2 outlets and 0 dead ends. Fix: "1-3 outlets: where the basin's
streams leave the group (one or two), plus any dead ends, plus UEUT's side channel with no parent".

**F5. KLUM does not hold the four side-channel paths.** README.md:115. KLUM holds 360222215, 360237491 and
360222216. The fourth, 360216952 (entered by 360884603, draining via 360216962 to the Skeena 360887278), and
all three of those lines are in **LSKE**, which was not run through SSNbler (README.md:121). So the SSNbler
check has not covered one of the four acceptance paths (findings.md "Acceptance": SSNbler on the subset that
connects the sites). Fix: "including KLUM, which holds three of the four side-channel paths in the tests (the
fourth, 360216952, is in LSKE, not run)", and say so where acceptance is claimed.

**F6. `junction_gap_m` "(0 when it touches)" is false for 52 lines.** extras/blue_line_paths/README.md:46.
`touch`: 18 of 71,331 have a gap > 0, max 0.993 m; `touch_round`: 34 of 29,691, max 0.999 m. "Touch" means
within 1 m, and 6 of these gaps (0.708-0.999 m) are exactly the 6 splits the main-flow-node rule exists for.
Fix: "(under 1 m when it touches, 0 for almost all)".

**F7. `topo_tolerance` does not flag "nodes closer than it that are not joined".** ssnbler_check.R:36.
SSNbler source: `outlets_only <- subset(nodexy_sf, nodecat == "Outlet")`, `st_buffer(outlets_only,
topo_tolerance)`, and an outlet whose buffer is crossed by more than one line is a "Dangling Node". Only
outlets are tested, against lines, not nodes. Fix: "topo_tolerance flags an outlet within that distance of a
line it does not join (a Dangling Node)".

**F8. "above 46,340 it requires its parallel path".** research/fwa_mainflow_tree.md:33. Source:
`if (n_edges >= max.edges ...) stop(...)`, `max.edges <- 46340`. At 46,340 exactly it already requires it.
README.md:102 and ssnbler_check.R:13 say "at 46,340 or more", which is right. Fix: "at 46,340 lines or more".

**F9. Provenance: neither script has run as committed.** research/fwa_mainflow_tree.md:3 says the numbers
were "Produced by: `extras/mainflow_tree/mainflow_tree.sh`". progress.md:16 says the steps were run through
`docker exec`, "not `mainflow_tree.sh` end to end". The only paths build (findings.md:106, 14:45-15:20 UTC =
07:45-08:20 PDT) predates commit 8826357 (13:02 PDT) that added `psql -1`, so `blue_line_paths.sh` in its
committed form has never run either. The SQL is the same and nothing in `blue_line_paths.sql` is forbidden
in a transaction block (no VACUUM, no CONCURRENTLY, no BEGIN/COMMIT), so I expect it to work, but the claim
is not a record. Fix: "Produced by: the SQL in `extras/mainflow_tree` and `extras/blue_line_paths`, run step
by step", or run `mainflow_tree.sh` end to end once before merging. The archive path in the same line
(`planning/archive/2026-10-issue-2-mainflow-tree/`) does not exist yet; check it matches what
`/planning-archive` creates.

**I1 (imprecise, not false). "rounds nodes" / "sets the precision nodes are rounded to ... as
qa_topology.sql does".** ssnbler_check.R:32-35, README.md:120, research/fwa_mainflow_tree.md:33. Source:
the rounding (`ndec <- get_decimals(snap_tolerance) - 1`, verified: 0 -> -1 = 10 m, 0.01 -> 1 = 0.1 m,
0.001 -> 2 = 1 cm) is used only to de-duplicate nodes (`ind.dup <- duplicated(rounded)`); kept nodes keep
their unrounded coordinates (`nodexy_mat[!ind.dup, ]`), and line ends are joined to them by distance <=
snap_tolerance (`pdist`). So snap 0.001 merges nodes sharing a 1 cm cell and joins ends within 1 mm, while
qa_topology.sql joins ends that share a 1 cm cell: the same precision, not the same test. Worth a clause,
since the two disagree at exactly the USKE/MSKE spots.

## Enumeration

Status: VERIFIED (how), FALSE (correct value), UNVERIFIABLE (why). "DB" = query on fresh-db 2026-10-09.

### (a) SSNbler / lines_to_lsn behaviour

| claim | file:line | status | evidence |
|---|---|---|---|
| parallel path required at 46,340 lines or more | README.md:102, ssnbler_check.R:13 | VERIFIED | source `max.edges <- 46340`, `n_edges >= max.edges` -> stop |
| "above 46,340 it requires its parallel path" | research:33 | FALSE | `>=`: at 46,340 or more (F8) |
| about 2 GB per worker (160,000-line subset) | README.md:102, ssnbler_check.R:13-14, research:33 | VERIFIED (recorded) | progress.md:19 8 PSOCK workers ~14 GB = 1.75 GB; findings.md:123 160,582 edges |
| memory roughly quadratic in lines | research:33, README.md:112-113 | VERIFIED | source: `pdist(from_xy, to_xy)` n x n, `pdist(node_coords, from_xy/to_xy)` ~n x n; 46,340 = floor(sqrt(2^31)) |
| 1.5 GB at 5,500 lines -> 39 GB at 24,000 | README.md:112-113, research:33 | VERIFIED (recorded) | grp_skeena_BABL.log "39109487488 peak memory footprint", 24,043 lines; UTRE 1.5 GB from findings.md:112 only (serial2.log's watchdog RSS for UTRE reads 3 GB, a different metric) |
| LSKE/BULK/FRAN "about 60 GB at that growth" | README.md:121 | VERIFIED (arithmetic) | 39 x (30,000/24,043)^2 = 60.7 |
| three at once coincided with three reboots | research:33 | UNVERIFIABLE | recorded in findings.md:113-114 only; not reproducible (and must not be) |
| writes node_errors.gpkg only when it finds errors, never removes one | ssnbler_check.R:28-29 | VERIFIED | source: `if (nrow(errors) > 0) st_write(... node_errors.gpkg ...)`, no unlink |
| snap_tolerance is the join distance | ssnbler_check.R:32 | VERIFIED | source: `which(x <= snap_tolerance)` on pdist of raw ends; `sum(x <= snap_tolerance)` for n_inflow/n_outflow |
| ndec = get_decimals(snap) - 1; 0.001 -> 1 cm, 0.01 -> 0.1 m, 0 -> 10 m | ssnbler_check.R:33-35, research:33 | VERIFIED | source `lines_to_lsn` + `get_decimals` (0 returns 0) |
| "rounds node coordinates" / "as qa_topology.sql does" | ssnbler_check.R:33-35, README.md:120, research:33 | VERIFIED, imprecise | rounding only de-duplicates; kept nodes unrounded; joins by distance (I1) |
| topo_tolerance "flags nodes closer than it that are not joined" | ssnbler_check.R:36 | FALSE | only Outlet nodes buffered; outlet crossed by >1 line = Dangling Node (F7) |
| outlets are nodecat == "Outlet" | ssnbler_check.R:66 | VERIFIED | source: `nodecat[outlet_nodes] <- "Outlet"`, converging nodes also "Outlet"; n.outlets computed the same way |
| SSNbler wants lines digitized in direction of flow | ssnbler_check.R:6-7, README.md:100 | VERIFIED | source: from = sample 0, outlet = n_inflow >= 1 & n_outflow == 0 on `to` ends |
| one-segment subset fails inside SSNbler's left_join | README.md:122 | VERIFIED | grp_nechako_TABR.log; source: `to_from_coords[first_indices, c("X","Y")]` with one row drops to a vector, so `left_join(by = c(X=..., Y=...))` fails (applies to SPAT/TAKL by the same code) |
| USKE/MSKE: two ends reported as an unsnapped node and a divergence (4 errors, one spot) | README.md:117-119, ssnbler_check.R:38-42 | VERIFIED | v2_/v3_ logs and lsn2_/lsn3_ node_errors.gpkg: pointids 1035/8627 (USKE), 9314/17982 (MSKE) each Unsnapped + Downstream Divergence, at the two ends of the short segment |
| unchanged at topo_tolerance 1 m and 1 cm | ssnbler_check.R:42 | VERIFIED | v2_ (topo 1 m) and v3_ (topo 1 cm) logs identical: 2 + 2 |
| at snap 0.01 the two ends round to one node, a Downstream Divergence | README.md:119-120, ssnbler_check.R:40-41 | VERIFIED | serial.log / tol0_ logs: 1 Downstream Divergence; coordinates round to the same 0.1 m (853970.0, 1311520.5; 878263.9, 1261699.1) |
| 24 of 26 groups 0 node errors | README.md:115, research:33 | VERIFIED | serial2.log: 26 groups, all exit 0 except USKE, MSKE |
| each group 1-3 outlets | README.md:116 | VERIFIED (count) | serial2.log outlets 1-3 |
| "the point where the basin leaves the group, plus any dead ends" | README.md:116 | FALSE | up to two exits; UEUT's no-parent side channel (F4) |
| KLUM holds the four side-channel paths | README.md:115 | FALSE | 360216952 is in LSKE, not run (F5) |
| the example `... klum.gpkg ... 1` expects 1 outlet | README.md:109 | VERIFIED | SQL per-group outlets KLUM = 1; v2_grp_skeena_KLUM.log outlets 1 |

### (b) psql / PostgreSQL behaviour

| claim | file:line | status | evidence |
|---|---|---|---|
| `psql -1` builds in one transaction; readers wait on the lock, not find tables missing or half filled | blue_line_paths.sh:10-12, README (paths):16 | VERIFIED by source reading, not tested | DROP TABLE takes AccessExclusiveLock held to commit; a blocked reader re-resolves the name after the lock (RangeVarGetRelidExtended retry, PG >= 9.2) and sees the new table. Concurrency cannot be tested with TEMP tables only |
| nothing in blue_line_paths.sql is barred inside a transaction block | blue_line_paths.sh:13 | VERIFIED | read the file: no VACUUM, CONCURRENTLY, BEGIN/COMMIT; DO blocks, CREATE INDEX, ANALYZE, CREATE OR REPLACE FUNCTION are fine |
| `-1` with ON_ERROR_STOP rolls back on error | blue_line_paths.sh:8,13 | VERIFIED | psql docs: with ON_ERROR_STOP, `-1` sends ROLLBACK on failure; `RAISE EXCEPTION` (cycle check) then keeps the old tables |
| `-1` path has run | (implied by README "Builds the tables in one transaction (about 35 min ...)") | UNVERIFIABLE | the only recorded build (07:45-08:20 PDT) predates the `-1` commit (13:02 PDT) (F9) |
| second job's rebuild waits for the first job's reads, then replaces tables under it | README (paths):17-18, pcic README | VERIFIED by source reading | each psql call is its own transaction; DROP waits for ACCESS SHARE holders of the current statement |
| "a NULL result (a test over no rows) prints name| and fails too" | mainflow_tree.sh:25, blue_line_paths.sh:15 | VERIFIED | `-tXA`: NULL prints empty -> `name|` -> `grep -qv '|t$'` matches; every qa.sql test is an aggregate or scalar, so none returns zero rows |
| `\copy ... FROM STDIN` under `-c` reads the redirected file | mainflow_tree.sh:17 | VERIFIED | `fwapg.mainflow_tree_overrides` holds exactly the CSV's row (868144443, exclude, note) |
| `\copy ... TO 'data/qa_topology.csv'` client-side, relative to the script dir | mainflow_tree.sh:23 | VERIFIED | `extras/mainflow_tree/data/qa_topology.csv` present: 8 cut_off + 473 dead_end rows |
| QA failure stops before export | mainflow_tree.sh:28-31, README:44 | VERIFIED | read: `exit 1` before the `\copy` export |

### (c) numbers about the data

| claim | file:line | status | evidence |
|---|---|---|---|
| 4,907,441 network segments | README:74, research:3 | VERIFIED | DB count |
| main flow 4,451,744 | README:78 | VERIFIED | DB `source='mainflow'` (1,523,004 lines) |
| reattached 58,447, 19,745 side channels, 11,491 km | README:79 | VERIFIED | DB count, distinct blk, sum(length_metre)/1000 |
| followed 177 on 110 lines | README:80, research:22 | VERIFIED | DB |
| excluded by override 1; tree 4,510,368 | README:81-82, research:25 | VERIFIED | DB total; table rows are post-exclusion (sum = 4,510,368) |
| 74,426 network split nodes | README:84, research:7 | VERIFIED | `mainflow_tree_qa_counts` and recomputed |
| 0 splits | README:84, research:25 | VERIFIED | `mainflow_tree_qa` has no split rows |
| 8 cut-offs, groups BARR GOLD KITR KUSR LFRA MESI OWIK TATR | README:85-87 | VERIFIED | DB |
| each cut-off "a reattached side channel" with two ways down | README:86, qa.sql:15-16, research:25 | FALSE | all `followed`; two ways down true (F1) |
| 28,870 main-flow cut-offs | README:85, research:10 | VERIFIED | `mainflow_tree_qa_counts` |
| 28,824 main-flow lines drain through a side channel | README:85, research:10 | VERIFIED | DB: main-flow lines whose parent is not main flow = 28,824 |
| 473 dead ends = 354 main stems (code junction, >1 cm) + 119 side channels (fallback) | README:88-90, qa.sql:23-25, research:25 | VERIFIED | DB: 354 `code` main stems, gap 1.153-8,275.8 m; 119 `side_fallback` (110 reattached + 9 followed) |
| 26,697 other tree outlets, lines with no parent: sea, borders, closed basins | README:90-91, qa_topology.sql:14-15 | FALSE | 26,713 = 26,697 main-flow + 16 reattached side channels with no parent, some mid-basin (F2) |
| reattachment alone: 7 split nodes, 97 cut-offs | README:92, research:21-22 | VERIFIED | re-emulated in TEMP tables: 7 split nodes, 97 cut-offs |
| 6 splits: tributary on a main-flow node given a side-channel parent 0.7-1 m away, near its top | README:93-94, research:21, mainflow_tree.sql:19 | VERIFIED | the 6 side channels in the emulated splits; their on-main-flow tributaries' gaps 0.708-0.999 m, junction on the side channel's top segment in each |
| 7th split is the Beaver River | README:94, research:23 | VERIFIED | emulated split includes 359572098 and 359024601 |
| 97 = 33 code_deferred + 32 side_fallback (>1 m), 21 touches within 1 m, 11 no parent | README:94-96, research:22 | VERIFIED | emulation: 33, 32, touch 2 + touch_round 19, none 11 |
| Beaver: two watershed_key lines on one code (359572098, 359024601), 6010 connectors, keep 359572098's | overrides.csv:2, README:27-28 | VERIFIED | DB: both have segments with blk = watershed_key on `200.692231.387879`; 868144443 is 359024601's 6010 segment |
| Nechako basin 8 outlets | README:124, research:25 | VERIFIED (count) | SQL basin outlets = 8 |
| "its mouth and 7 dead ends ... LEUT, UEUT, TAKL, FRAN, LTRE, STUR" | README:124-125, research:25 | FALSE | mouth + 6 dead ends + UEUT 355995011 with no parent (F3) |
| Skeena basin 1 outlet | README:123, research:25 | VERIFIED | SQL: LSKE 360887278 only |
| LSKE/BULK/FRAN 29,000-30,000 lines | README:121 | VERIFIED (rounded) | 29,266 / 30,046 / 30,134 |
| Skeena share of SPAT, TAKL and Nechako share of TABR one segment each | README:121-122 | VERIFIED | skeena.csv/nechako.csv and DB |
| KLUM 24,732 lines, 0 errors, 1 outlet | progress.md, README:115 | VERIFIED | DB 24,732 (MSKE also exactly 24,732, checked, a coincidence) |
| USKE 239055049 1.6 cm, MSKE 141013301 2.9 cm, main flow, plain chain | README:117-118, research:33, ssnbler_check.R:39-40 | VERIFIED | DB lengths 0.0161 / 0.0293 m, edge 1000, mainflow; neighbours: one tree segment in and out at each end (the other segments there are side channels not in the tree) |
| SQL finds no split at those nodes (1 cm) | README:119 | VERIFIED | 0 splits province-wide |
| 26 Skeena 1450 connectors at measure 0, 24 main flow, 360222215 and 360237491 side channels | qa.sql:31-32, research:11 | VERIFIED | DB 24 of 26 main flow; the two non-main are those |
| entries 297.7, 325.3, 1386.5, 1017.0 | qa.sql:53-56 | VERIFIED | `blk_parents` junction_measure for the 4 tributaries |
| 360216952 kept to 1699.6 | qa.sql:49 | VERIFIED | DB max(drm + length) of kept segments 1699.6 |
| the Chilako is one main line at `100.567134.069486` | qa.sql:81-83 | VERIFIED | DB count 1 |
| issue table: 41-1,023 / 0 / 7-472 / 18-475 / 30-1,513 | research:9 (via findings) | VERIFIED | recomputed for the 14 groups, edge 1425 excluded: identical |
| junction measure up to 1.5e-4 m above the node | research:27 | VERIFIED | DB: 19,806 touch junctions with the mouth at a node, max 1.467e-4 m |
| 366 splits with a strict `<` | research:27 | UNVERIFIABLE | recorded in review-plan.md:7 only (a reviewer emulation); not re-run |
| FWA digitizes side channels from the downstream end | README:33-34, research:31 | VERIFIED | DB Z: on 19,745 reattached lines, Z rises from measure 0 in 15,980, flat 3,762, falls 3 |
| paths: about 35 min, 1.2 ms per line, almost all touches | README (paths):16, research (positions):19 | VERIFIED (recorded) | findings.md:106 (35 min 17 s incl. ~1 min snapshot; 3.2 s / 2,634 lines); 1.2 ms x 1,570,499 = 31 min |
| max 17 lines on a path, mean 4.18 | fwa_position_codes.md:19 | VERIFIED | DB `blk_paths`: 1,570,499, max 17, avg 4.18 |
| tree build about 1 min | README:42 | VERIFIED (recorded) | progress.md:15 |
| junction_gap_m 0 when it touches | README (paths):46 | FALSE | 52 touch/touch_round gaps > 0, up to 0.999 m (F6) |
| touch within 1 m; fallback within 1 km | README (paths):25,29 | VERIFIED | SQL `ST_DWithin(..., 1)`, `ST_DWithin(..., 1000)` |
| Okanagan no path; Kitsumkalum path to Skeena; Cayoosh path to 356364114 | paths qa.sql | VERIFIED | DB |
| main-flow-only and dropped-edge-type counts "both thousands" | qa_topology.sql:89-90, qa.sql test 2 | VERIFIED | 74,426 and 28,870 |
| Produced by mainflow_tree.sh | research:3 | FALSE | steps run individually (progress.md:16) (F9) |
| measurements in `planning/archive/2026-10-issue-2-mainflow-tree/` | research:3 | UNVERIFIABLE | path does not exist until `/planning-archive` |

## Not findings (checked)

- No tree segment is shorter than 1 cm province-wide (min 1.6 cm in the two basins), so SSNbler's
  `snap_tolerance < shortest line` stop cannot fire at 0.001 (nor at 0.01).
- Two touch junctions land 1.4 and 8.5 mm up a segment rather than at its node; both parents are main flow,
  so the 1 cm reattachment tolerance does not touch them.
