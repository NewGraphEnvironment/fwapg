# Review round 1: SSNbler fix-pdist-precision-parallel-unsnapped vs upstream/develop (d3918f1)

## Clean
No issues found.

## What was checked (probes run in a temp copy, the live repo untouched)

- combine_node_chunks() against the serial computation: 300 randomized cases (1-60 nodes,
  1-40 to-points drawn from a 15-point pool so exact duplicates are frequent, a random chunk
  count from 1 to n, node_xy as matrix and as data.frame). All 300 `identical()`, including
  types (integer, unnamed) and the empty `integer(0)` case.
- One-row other_xy and a one-row zero_pairs (z[, 1] drops to a scalar): cbind still gives
  a 1x2 matrix, so the combine works.
- `$` partial matching in combine_node_chunks(): the keys are n_flow / snap_check /
  zero_pairs, and none is a prefix of another, so `chunks[[1]]$zero_pairs` is NULL for "from".
- Lazy default `block_size = max(1, floor(5e6 / NROW(b)))` is evaluated after `b` is
  coerced, and the early return covers nrow(b) == 0 (Inf block size never reaches seq()).
- Column use: every caller passes 2-column x/y (from_xy/to_xy are built from x[1:2],
  node_coords from to_from_coords[, 1:2]), so dist_xy's use of columns 1 and 2 matches
  pdist, which used all columns.
- No remaining pdist reference in R/, NAMESPACE, DESCRIPTION, tests or vignettes (only a
  test comment). withr is in Imports, so the test's withr::local_tempdir() is declared.
- Workers: pdist_node_coords is exported with the SSNbler namespace as its environment, so
  on the worker dist_xy resolves in the installed namespace (this branch). Correct for
  R CMD check; under load_all with an older install it would fail, which is a dev-env
  matter, not a package bug.
- Test file: all 6 blocks pass under test_file(); the parallel block passes with
  NOT_CRAN=true (it skips without it, by design: skip_on_cran).
- Restore-the-bug: with dist_xy patched in the namespace to as.matrix(pdist::pdist(a, b)),
  "a few-cm line at BC Albers coordinates" goes red (3 failures) and "chunked node
  distances agree" goes red (1 failure). The two dist_xy unit blocks stayed green under
  that patch only because test code reaches the package-env binding, not the patched
  namespace one (load_all's two bindings), so that is a probe limitation, not a weak test.
- dist_xy vs pdist at coordinates ~0-100: max difference 1.2e-5, which looks like pdist
  working in single precision; consistent with (and stronger than) the NEWS framing.

## Notes outside the diff (not findings)

- A one-edge network fails in lines_to_lsn() at R/lines_to_lsn.R:622 (dplyr left_join:
  "Join columns in `x` must be present") on the serial path, and identically on base
  d3918f1, so it is pre-existing and unrelated. It means the simplest route to a one-row
  split_matrix() chunk (n_edges = 1, use_parallel = TRUE) is not reachable end to end; with
  the 500-row cap a one-row last chunk otherwise needs roughly > 250k edges, so fix 3 is
  covered by the split_matrix unit test only, as the PR intends.
- The serial rid_confl uses apply(..., 2, which(...)) without simplify = FALSE while
  pdist_rid_confl() uses simplify = FALSE; the serial form can simplify to a matrix when
  every column has the same number of matches. Pre-existing, untouched by this diff.
