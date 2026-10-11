# Task: Fix SSNbler's false topology errors on a fork, PR upstream, re-run the SSNbler check (#16)

SSNbler 1.1.2 reports false node errors on FWA data (pet221/SSNbler#8). Fix it on a fork, offer the fix upstream as a PR with tests, and re-run `extras/mainflow_tree/ssnbler_check.sh` against the fixed version. Needed before SSN2 modelling on the main-flow tree, which builds its networks with SSNbler.


## Phase 1: Fork and baseline
- [ ] Fork `pet221/SSNbler` to NewGraphEnvironment, clone it to `~/Projects/repo/SSNbler`, and branch `fix-pdist-precision-parallel-unsnapped` off `main`
- [ ] Baseline: `devtools::test()` and `ssnbler_reprex.R` against the unmodified clone (`devtools::load_all`), recording errors A and B in findings.md

## Phase 2: Tests first (fork)
- [ ] `tests/testthat/test-topology_precision.R`: a chain of 3 lines at BC Albers coordinates (878000, 1261000) whose middle line is 3 cm long; `check_topology = TRUE`, `snap_tolerance = 0.001`; expect no `node_errors.gpkg`. Plus the same chain near the origin as the control.
- [ ] Unit test of the distance helper against `sqrt(rowSums((a-b)^2))` at magnitudes 10⁰–10⁶, including pairs 1 mm apart and identical points (exactly 0)
- [ ] Parallel test: 700 lines, the 3 cm line at 650 (two node chunks), `use_parallel = TRUE, no_cores = 2`; node categories and errors identical to serial. `skip_on_cran()` because it starts a cluster.
- [ ] A test with a duplicate to-node pair split across two chunks: the parallel path flags it the same way serial does
- [ ] Confirm the new tests fail on the unmodified code. This is the restore-the-bug check.

## Phase 3: Fix (fork)
- [ ] Internal helper `dist_xy(a, b)`: an exact Euclidean distance matrix from coordinate differences, filled in row blocks into a preallocated matrix (peak memory no higher than pdist + `as.matrix`)
- [ ] Replace all 5 pdist() calls with it. Drop `importFrom(pdist, pdist)` and pdist from DESCRIPTION Imports and from foreach's `.packages`.
- [ ] Parallel path: each chunk returns n_flow, snap_check and the zero-distance (node, to-edge) pairs with global node rows (offset by the chunk start). `get_pdist_nodes()` derives `dbl_tonodes` (to-ends with more than one zero-distance node) and `unsnapped_tonodes` over the whole node set.
- [ ] `split_matrix()`: `drop = FALSE`
- [ ] NEWS.md entry under a dev version (1.1.2.9000), citing pet221/SSNbler#8
- [ ] Measure the serial path on a ~20k-line group (USKE) before and after the change, to confirm the helper does not raise peak memory or run time

## Phase 4: R CMD check (fork)
- [ ] `devtools::check()`: 0 errors and 0 warnings, with any NOTE explained
- [ ] Push the fork branch and record the pinned commit SHA

## Phase 5: Acceptance test (fwapg)
- [ ] Install the fork at the pinned SHA (`pak::pak("NewGraphEnvironment/SSNbler@<sha>")`)
- [ ] `ssnbler_check.sh`: USKE and MSKE serial, expecting 0 node errors each
- [ ] `ssnbler_check.sh` on the whole Skeena (parallel), expecting 0 node errors and 1 outlet
- [ ] The issue's shift test with **no** shift on the USKE/MSKE exports, expecting 0 and 0
- [ ] `ssnbler_reprex.R`: clean on both paths
- [ ] If anything is still flagged, fix it in the fork and repeat Phases 4 and 5

## Phase 6: fwapg docs
- [ ] `extras/mainflow_tree/README.md`: the re-run results, with SSNbler installed from the fork at the pinned commit
- [ ] `research/fwa_mainflow_tree.md`: revise the SSNbler facts (precision, parallel), the results and the **Verified** line
- [ ] `ssnbler_check.R` / `ssnbler_reprex.R` header comments: name the fixed version, and change the pdist comment to say what the fork does
- [ ] Edit the fwapg#16 issue body: exact distances instead of the origin shift, and why (the measurement)

## Phase 7: Upstream PR (gated)
- [ ] Draft the PR body against `pet221/SSNbler` referencing #8, and show it to you. **Nothing is posted without your approval.**
- [ ] Once approved, open the PR and record its link in the fwapg README and research file

## Validation
- [ ] Tests pass (fork: `devtools::test()` + `check()`; fwapg: acceptance runs)
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion


## Validation

- [ ] Tests pass (fork: `devtools::test()` + `check()`; fwapg: acceptance runs)
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
