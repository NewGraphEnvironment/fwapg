# Review round 2: diff 218a47f...HEAD (fwapg#2)

Reviewer: subagent, 2026-10-09. Scope: extras/blue_line_paths/*, extras/pcic_crosswalk/* (rename),
extras/mainflow_tree/*, research/*.md, and the round 1 fixes (f3230fd, 8826357, snap_tolerance 0.001).
Checklist: extras/mainflow_tree/data/review-checklist.md (Mechanisms, shell, Docker/Postgres, R).
Database probes were read-only (SELECT and TEMP tables on fresh-db). SSNbler was not run; its source was
read with deparse (SSNbler 1.1.2).

Verdict: no bugs. None of the findings below changes a result today. Two are comments or docs that state
something false, and one is a warning that is in two READMEs but not in the third.

## Findings

- **[fragile]** extras/mainflow_tree/ssnbler_check.R:32-35. The comment explaining the 0.001 fix has two
  errors. Neither changes the result today.
  1. "(to 1 m when it is 0)" is wrong. `get_decimals(0)` returns 0, so `ndec = -1`, and
     `round(x, -1)` rounds to **10 m**. Measured: `round(1234.5678, -1)` is 1230. A tolerance of 1 or more
     rounds to 1 m. SSNbler's default is `snap_tolerance = 0`, so anyone who believes the comment and
     drops the argument gets 10 m nodes, not 1 m. The brief for this round made the same mistake
     ("0 when snap_tolerance is 0").
  2. The comment treats `snap_tolerance` as a rounding setting only. It is also the distance SSNbler
     uses to match ends to nodes:
     - `rid_confl` uses `which(x <= snap_tolerance)` to connect edges;
     - `n_inflow` and `n_outflow` use `sum(x <= snap_tolerance)` to classify nodes.

     So going from 0.01 to 0.001 also cut the matching distance tenfold, from 1 cm to 1 mm.

  Why it is safe on the current tree (checked):
  - Only one 1 cm cell in the tree holds ends that are not exactly equal (COWN, segments 868144274,
    868144275 and 710277111). They are 0.125 mm apart, well within 1 mm.
  - Every tree segment shorter than 3 cm has |dx| or |dy| over 1 cm, so no segment's two ends round to
    the same node.

  Fix: change the comment to "(to 10 m when it is 0, to 1 m when it is 1 or more)", and say that 0.001 is
  also the matching distance.

- **[fragile]** extras/pcic_crosswalk/README.md. Fix 3 added the warning not to run `pcic_crosswalk.sh` and
  `mainflow_tree.sh` at the same time. It is in extras/blue_line_paths/README.md and
  extras/mainflow_tree/README.md:41, but not in the PCIC README. That README is the one read by whoever
  starts the PCIC job while the tree job is running. The cost is now low:
  - `psql -1` means a reader waits for the rebuild rather than seeing missing or half-built tables.
  - The rebuild gives the same result every time. Measured: the parent pick (`is_expected DESC,
    touched_depth DESC, gap`) has no tie among the eligible candidates for any of the 101,022
    touch and touch_round lines. As a control, 157 of those lines do tie on depth alone, so the query
    can find ties.

  So running both jobs at once mainly costs a lock wait. Fix: one line in the PCIC README's Processing
  section pointing to extras/blue_line_paths.

- **[fragile]** research/fwa_position_codes.md:19. The line edited in this diff adds "measured 2026-10-09"
  but keeps the old "max 16 hops, mean 3.9". The current `fwapg.blk_paths` (1,570,499 paths) gives
  `max(cardinality(path_blks)) = 17` and a mean of 4.18. Fix: derive both numbers from the table, or
  drop them.

## Notes (not findings)

- extras/mainflow_tree/mainflow_tree.sh:25-31. A QA failure stops the export, but the failing build is
  already in `whse_basemapping.fwa_stream_networks_mainflow_tree`, because mainflow_tree.sql drops and
  rebuilds it before QA runs. "nothing exported" is true of the CSV only. blue_line_paths.sh and the PCIC
  job work the same way, so this is the existing pattern rather than something this diff introduced.

## Checked and not a finding

- **Fix 1 (stale node_errors.gpkg).**
  - SSNbler's `lines_to_lsn` writes node_errors.gpkg only when `nrow(errors) > 0` (source lines
    308-320), so removing the file before the call is the right fix.
  - nodes.gpkg is always rewritten (`overwrite = TRUE`, `delete_dsn = TRUE`), so it cannot be stale.
  - `unlink()` returns 1 rather than raising an error when it fails. A file that could not be deleted
    would make a clean run exit 1, which fails toward fail, not toward pass.
- **Fix 2 (README outlet count).** The example now passes 1. The script fails on `!=`, and the README
  says "other than". A non-numeric third argument gives `NA`, `if (NA)` raises an error, and the script
  exits 1.
- **Fix 3 (`psql -1`).**
  - blue_line_paths.sql has no statement that cannot run inside a transaction block: no VACUUM, no
    CONCURRENTLY, no BEGIN or COMMIT. ANALYZE is allowed in a transaction.
  - After waiting on the lock, a reader re-resolves the table name (RangeVarGetRelidExtended retries on
    invalidation), so it reads the new table rather than failing on a dropped OID.
  - `blk_on_or_upstream` is LANGUAGE sql, so it holds no cached plan pinned to the old OID.
  - A deadlock needs one transaction that reads blk_paths and then blk_parents. None does:
    mainflow_tree.sql and qa_topology.sql read only blk_parents, and PCIC 04-07 and qa.sql read only
    blk_paths. Postgres would also detect a deadlock and fail loudly.
- **Rename.** `grep` for `pcic_blk`, `pcic_on_or_upstream`, `crosswalk01`, `pcic_touches`, `pcic_blks`,
  `pcic_code_junctions` and `pcic_side_fallback` outside planning/ finds nothing. The scripts keep their
  executable bit (100755).
- **Geometry and the 1 cm grid.** `fwa_stream_networks_sp.geom` is LINESTRING with coord_dimension 4, and
  there are 0 multipart segments. The shortest tree segment is 1.39 cm, so SSNbler's own stop on edges
  shorter than `snap_tolerance` (source lines 41-46) does not fire at 0.001.
- **README numbers checked against the database.** These all match:
  - by source: 4,451,744 mainflow, 58,447 reattached (19,745 lines), 177 followed (110 lines);
  - total 4,510,368;
  - 8 cut-offs, in BARR, GOLD, KITR, KUSR, LFRA, MESI, OWIK and TATR;
  - 473 dead ends: 354 main stems with a code junction, 119 side channels with a side_fallback junction;
  - 74,426 network split nodes and 28,870 main-flow cut-offs;
  - the override segment 868144443 is absent from the tree.
- **mainflow_tree.sql.**
  - The walk records the entry measure on the parent at both levels.
  - `UNION` and acyclic parents mean the recursion ends.
  - Following cannot add a split: count = 1 at the frontier node, and `DISTINCT` covers two frontier
    segments that meet at one node.
  - The 1000-round limit raises an error.
  - `LIKE net_nodes` and `SELECT n.*` keep the same column order.
- **qa.sql.**
  - Every test returns one row.
  - Empty CTEs fail rather than pass: `count(*) = 1` on chilako, `EXISTS` on the path to the Nechako,
    and `count(*) = 4` on the side channels.
  - The shell treats empty output, `name|` and any `|f` as a failure.
