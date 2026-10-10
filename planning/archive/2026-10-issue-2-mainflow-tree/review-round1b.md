# Review round 1b: diff 218a47f...HEAD (fwapg#2)

Reviewer: subagent, 2026-10-09. Scope: extras/blue_line_paths/*, extras/pcic_crosswalk/* (rename),
extras/mainflow_tree/*, research/*.md. Checklist: extras/mainflow_tree/data/review-checklist.md
(Mechanisms, shell, Docker/Postgres, R sections).

## Findings

- **[bug]** extras/mainflow_tree/ssnbler_check.R:267-276. A stale `node_errors.gpkg` fails a clean run.
  The script decides "node errors" by `file.exists(file.path(args[2], "node_errors.gpkg"))`. SSNbler 1.1.2
  `lines_to_lsn(overwrite = TRUE)` writes that file only when `nrow(errors) > 0` and never deletes an old
  one. The code shows this; it was not run. Its own message for the clean case is "0 topology errors
  identified. node_errors.gpkg not written to file." So if you re-run into the same `<lsn directory>`
  after a run that had errors (the README example always uses `data/lsn_skeena`), the script prints the
  old run's error table and exits 1 on a network that is clean. It fails toward fail, not pass, but the
  output gives the wrong verdict and the wrong error rows. Fix: `unlink(args[2], recursive = TRUE)`
  before `lines_to_lsn()`, or remove `node_errors.gpkg` before the call.

- **[fragile]** extras/mainflow_tree/README.md:99-106 against ssnbler_check.R:276-277. The README says
  the check "fails on any node error or more than one outlet". The documented command passes no third
  argument, so the outlet count is never tested: a Skeena subset with extra outlets (for example, a dead
  end or a cut-off included) exits 0. The script also tests "a different number" (`!=`), not "more than
  one". This is a guard that fails toward pass for anyone who follows the README. Fix: put `1` in the
  example command, or reword the README to say the outlet test needs `[expected outlets]`.

- **[fragile]** extras/blue_line_paths/sql/blue_line_paths.sql:180-245 and 297-327, as now called from
  both extras/pcic_crosswalk/pcic_crosswalk.sh:133 and extras/mainflow_tree/mainflow_tree.sh:12.
  `fwapg.blk_parents` and `fwapg.blk_paths` used to be private to the PCIC job (`pcic_` prefix, dropped
  at the end of the job). They are now shared, and each job rebuilds them first, about 35 min per
  rebuild. The rebuild is `psql -f` in autocommit mode: `DROP TABLE`, then `CREATE`, then several
  `INSERT`s and a `DO` loop, each committed separately. If one job starts while the other is reading the
  tables, the reader sees one of three states:
  - the table is missing;
  - `blk_parents` is partly filled. Example: `qa_topology.sql`'s dead-end test, or step 2 of
    `mainflow_tree.sql`, running mid-rebuild;
  - `blk_paths` is gone in the middle of PCIC steps 04-07.

  A partly filled `blk_parents` gives wrong results without an error. The `mainflow_tree.sql` walk then
  silently drops reattachments, and the QA can pass or fail for the wrong reason. Before this diff the
  two jobs could not collide.

  Fix options:
  - build into staging tables, then swap with `ALTER TABLE ... RENAME` in one transaction;
  - run the build with `psql -1`, so the lock blocks readers rather than showing them partial state;
  - at minimum, add a line in `blue_line_paths/README.md` saying the jobs must not run concurrently.

## Checked and not a finding

- Rename completeness: `grep -rn 'pcic_blk\|pcic_on_or_upstream\|crosswalk01\|pcic_touches\|pcic_blks\|pcic_code_junctions\|pcic_side_fallback'`
  outside planning/ and .git finds nothing. Every reference in 03-07, the README and the research note
  uses `blk_paths` / `blk_on_or_upstream`. The relative call `../blue_line_paths/blue_line_paths.sh`
  matches how `pcic_crosswalk.sh` is already run (from its own directory, which its `sql/` and `data/`
  paths already need). A QA failure in the child exits 1, which stops the parent under `set -e`.
- `fwa_stream_networks_sp.geom` is LINESTRING (coord_dimension 4), so `ST_StartPoint` / `ST_EndPoint` in
  `net_nodes` and `qa_nodes` never return NULL.
- The override row 868144443 exists. It is the top segment of 359024601 (a 6010 connector), so excluding
  it creates no cut-off; the 8 `cut_off` rows are all reattached side channels, as the README says. If a
  later FWA re-release changes ids, the override silently stops matching, but the Beaver River split it
  covers would then fail the "no splits" test, so that case is caught.
- Step 3 (following) cannot add a split: the segment it adds is the only network segment whose upstream
  node is the frontier node. `DISTINCT` removes duplicates when two frontier segments meet at one node,
  and the 1000-round limit raises an error.
- Step 2 recursion ends because the parents are acyclic, which `blue_line_paths.sql` enforces with
  `RAISE`, and `UNION` removes duplicates. `on_mainflow` is checked against the line being walked, at
  every level of the recursion.
- Shell QA guards: if psql fails, `set -e` stops the script at `qa=$(...)`. An empty result fails. A
  NULL result prints `name|` and fails. No test name contains `|`. Every QA statement returns one row.
- Table and column order in `next_segments` / `tree_nodes` / `frontier` (`LIKE net_nodes`, `SELECT n.*`)
  line up, so `INSERT ... SELECT *` is safe.
- `data/` and `*.gz` outputs are gitignored.
