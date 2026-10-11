# /code-check round 2: fwapg branch 16 vs newgraph (HEAD a607166)

## Findings

- **[severity: fragile]** extras/mainflow_tree/ssnbler_check.R:25-30. A CRAN install made with pak gets the label `standard`, not `CRAN`. The comment says CRAN is labelled, but the code tests `RemoteType` before `Repository`. pak writes `RemoteType: standard` for any repository install, CRAN or r-universe, and it also keeps `Repository: CRAN`, so that branch never runs. Measured by running the label function over this machine's library: `abind` (pak, CRAN) gives `standard`, `BiocGenerics` (pak, r-universe) gives `standard`, `cffr` (install.packages, CRAN) gives `CRAN`, `fly` (pak local) gives `local`, `flooded` (R CMD INSTALL) gives `local`, and a GitHub install gives `owner/repo@sha7`. The README installs with pak, and the planned switch back to CRAN will probably use pak too, so that is the path these runs will take. runs.log will then read `ssnbler: 1.1.2 standard`. The version still separates CRAN 1.1.2 from the fork, but `standard` does not say which repository the package came from, which is what this fix was meant to report. Fix: when `RemoteType` is `standard` (or whenever `Repository` is set), print `Repository` first, for example `else if (!is.null(d$Repository)) d$Repository else if (!is.null(d$RemoteType)) d$RemoteType`. Otherwise reword the comment so it matches what the code prints.

## Checked, no defect

- **Summary extraction under `set -euo pipefail` with the EXIT trap (ssnbler_check.sh:184-186).** Tested the two new lines on their own, with the same `set -euo pipefail` and an `exit "$final"` trap, against four logs: one with no matching lines, one with both lines, one with two `ssnbler:` lines and one that does not exist. All four reached the summary with rc 0, and the fallbacks printed `relationships: ?` and `ssnbler: ?`. The `|| true` after `grep | head | tr` catches grep's status 1 under pipefail. A SIGPIPE from `head -1` is not reachable here.
- **The relationships guard (ssnbler_check.R:85-91).** In the installed fork, `relationships.csv` is always written, including when node errors are found. There is no early return, and `write.table` overwrites it every run, so the guard cannot read a stale file. The guard compares an outlet count taken from nodes with one taken from edges. Those two counts can differ only at a converging or complex outlet, and that is already a node error, so a clean network cannot fail the guard falsely. All counts are integers, so `cat` cannot print one in scientific notation and break the grep.
- **End-to-end run.** Ran `ssnbler_check.R` on a copy of `t_lkel.gpkg` with a temporary lsn directory. It printed `ssnbler: 1.1.2.9000 NewGraphEnvironment/SSNbler@37ca338`, then `relationships: 2217  expected: 2217  edges into two: 0`, then `node errors: 0  outlets: 1`, and exited 0.
- **Numbers in README.md and research/fwa_mainflow_tree.md, checked against findings.md, runs.log, the logs, the issue #16 body and `lsn_basin_skeena/relationships.csv`.**
  - Fork peaks of 17-18 GB (USKE), 24-28 GB (MSKE), 3.8 GB (Bulkley), and 10.9 GB and 54 min (Skeena) match runs.log.
  - Skeena: 261,763 relationship rows, 0 duplicated `fromedge`, 261,764 lines, read directly from the csv.
  - The per-group logs give 21654/24731/52292 relationships, all as expected.
  - The shift results (integer offset: USKE 0, MSKE 1; bounding-box corner: MSKE 0, USKE 1) match the issue's evidence section.
  - 9 mm at 10⁵ m and 1.6 cm at 2×10⁵ m match findings.md.
  - Float spacing of 0.0625 m in [2^19, 2^20) and 0.125 m above 1,048,576 m is correct.
  - runs.log reads `local` for the fork runs of the Skeena and the Bulkley, and the second USKE and MSKE runs read `37ca338`. Both match the README's caveat.
- **ssnbler_reprex.R.** The `requireNamespace("pdist")` guard is correct, and pdist is used nowhere else.

## Note (not a defect)

- README.md: "Re-run on the fork at 37ca338 (2026-10-11)" and "on the fork, ... (2026-10-11)". The first fork runs of USKE, MSKE and the Bulkley are stamped 2026-10-10 23:15-23:24 in runs.log, local time. Only the Skeena run and the pak runs fall on 2026-10-11.
