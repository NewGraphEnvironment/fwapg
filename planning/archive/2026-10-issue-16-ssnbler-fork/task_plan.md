# Task: Fix SSNbler's false topology errors on a fork, PR upstream, re-run the SSNbler check (#16)

SSNbler 1.1.2 reports false node errors on FWA data (pet221/SSNbler#8). Fix it on a fork, offer the fix upstream as a PR with tests, and re-run `extras/mainflow_tree/ssnbler_check.sh` against the fixed version. Needed before SSN2 modelling on the main-flow tree, which builds its networks with SSNbler.


## Phase 1: Fork and baseline
- [x] Fork `pet221/SSNbler` to NewGraphEnvironment, clone it to `~/Projects/repo/SSNbler`, and branch `fix-pdist-precision-parallel-unsnapped` off `main`
- [x] Baseline: `devtools::test()` and `ssnbler_reprex.R` against the unmodified clone (`devtools::load_all`), recording errors A and B in findings.md

## Phase 2: Tests first (fork)
- [x] Before-snapshot: `MF_streams` (EPSG:5070, ~3e6 m) through `lines_to_lsn()` on both paths with unmodified code; save `relationships.csv`, `noderelationships.csv`, nodecat and node_errors to diff after the fix (review G7)
- [x] `tests/testthat/test-topology_precision.R`: the 3-line chain at the pinned coordinates (878000, 1261000), the middle line 3 cm long, `snap_tolerance = 0.001`, in `withr::local_tempdir()`; expect no node errors and `relationships.csv` exactly 1→2, 2→3. Control: the same chain near the origin. A comment explains why the coordinates are pinned (pdist reads 3 cm as 0 there, but only ~63% of random BC Albers positions do)
- [x] Unit tests of `dist_xy()`: offsets exact in binary (2^-10; a 3-4-5 triangle scaled by 2^-7) at 10^0-10^6 checked with `expect_identical`, identical points exactly 0, rectangular/data.frame/1-row inputs, and a block size forcing several blocks plus a remainder (review G5)
- [x] Unit test of the parallel combiner without a cluster: `lapply` over `split_matrix(node_xy, 2)` with duplicate node rows within one chunk and across the boundary (351/352 of 701), compared with the serial `which(colSums(D == 0) > 1)` / `which(rowSums(D[, dbl, drop = FALSE] == 0) > 0)` on the full matrix (review B1: unreachable through `lines_to_lsn()` once distances are exact)
- [x] `split_matrix()` unit test: 10 rows into 4 chunks give 3/3/3/1, each a matrix keeping its rownames (review G4)
- [x] Parallel test: 700 lines with the 3 cm line at 650, `use_parallel = TRUE, no_cores = 2`, node categories, errors and relationships identical to serial; `skip_on_cran()`

## Phase 3: Fix (fork, branched from upstream `develop`, 1.1.2.9000)
- [x] Internal `dist_xy(a, b)`: exact Euclidean distances from coordinate differences, filled in row blocks into a preallocated matrix; replace all 5 pdist() calls; drop `@importFrom pdist pdist` (R/SSNbler-package.R), pdist from Imports and from foreach `.packages`; `document()`
- [x] Parallel path: `pdist_node_coords()` returns chunk-local zero-distance (node, edge) pairs; `get_pdist_nodes()` offsets them by real chunk sizes, derives `dbl_tonodes` and `unsnapped_tonodes` globally (`sort(unique())`), list handling rather than `.combine = 'c'`
- [x] `split_matrix()`: `drop = FALSE`
- [x] ~~Separate commit~~ not made, measured instead (findings.md): from/to/node coordinates from the vertices (`st_coordinates()`) instead of `st_line_sample()`, whose to-ends drift up to 2.3e-10 m (5 USKE, 3 MSKE lines), hidden today only by the rounding-bin merge plus the `removed_nodes` suppression (review G1); kept out of the PR if it touches more than the end-point extraction
- [x] NEWS.md bullets under "(development version)", citing pet221/SSNbler#8
- [x] Install the branch (`R CMD INSTALL .`): parallel workers load the installed SSNbler, not `load_all()` (review B2)
- [x] `devtools::test()` green; MF_streams after-snapshot identical to the before-snapshot on both paths
- [x] Restore-the-bug, one defect at a time on an installed reverted tree: precision only, offsets only, `drop` only; each makes at least one new test fail

## Phase 4: R CMD check (fork)
- [x] `devtools::check()`: 0 errors and 0 warnings, with any NOTE explained
- [x] Push the fork branch and record the pinned commit SHA

## Phase 5: Acceptance test (fwapg)
- [x] `ssnbler_check.R` prints `packageVersion("SSNbler")` and the RemoteSha, so each runs.log line names its build (review AC3); during iteration install from the local clone, pin the SHA once at the end
- [x] Before-run baseline is runs.log 2026-10-10: USKE 4 errors 28.0 GB, MSKE 4 errors 37.0 GB, Skeena 6 errors 19.9 GB, Bulkley 0 errors 3.5 GB
- [x] `ssnbler_check.sh`: USKE and MSKE serial, expecting 0 node errors each, peak memory no higher than baseline; the fresh exports still hold 239055049 (1.6 cm) and 141013301 (2.9 cm)
- [x] `ssnbler_check.sh` on the whole Skeena (parallel), expecting 0 node errors and 1 outlet
- [x] relationships checks on all three: no `fromedge` repeated, rows = edges - outlets (review G3/AC1)
- [x] Regression: Bulkley (parallel, 52k lines) re-run, `relationships.csv` and `noderelationships.csv` identical to the existing `lsn_basin_bulkley` (review AC4)
- [x] The issue's shift test with no shift and an `unlink()` of node_errors, on the existing USKE/MSKE exports, expecting 0 and 0
- [x] `ssnbler_reprex.R`: clean on both paths (its own `pdist::pdist()` line guarded by `requireNamespace`)
- [x] If anything is still flagged, fix it in the fork and repeat Phases 4 and 5 (nothing flagged)

## Phase 6: fwapg docs
- [x] `extras/mainflow_tree/README.md`: the re-run results, with SSNbler installed from the fork at the pinned commit
- [x] `research/fwa_mainflow_tree.md`: revise the SSNbler facts (precision, parallel), the results and the **Verified** line
- [x] `ssnbler_check.R` / `ssnbler_reprex.R` header comments: name the fixed version, and change the pdist comment to say what the fork does
- [x] Edit the fwapg#16 issue body: exact distances instead of the origin shift, and why (the measurement)

## Phase 7: Upstream PR (gated)
- [x] Draft the PR body (`upstream_pr_draft.md`) against `pet221/SSNbler` `develop` (asking the maintainer which base they want; CI runs on PRs to `main`) referencing #8, saying the `dbl_tonodes` mechanism cannot fire with exact distances, plus the rounding-bin note (`snap_tolerance = 0` gives 10 m bins), and show it to you. **Nothing is posted without your approval.**
- [ ] Once approved, open the PR and record its link in the fwapg README and research file

## Validation

- [x] Tests pass (fork: `devtools::test()` + `check()`; fwapg: acceptance runs)
- [x] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [x] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
