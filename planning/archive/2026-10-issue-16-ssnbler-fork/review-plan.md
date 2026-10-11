# Plan review: #16 (Plan agent, 2026-10-11)

Read-only review of the baseline task_plan.md against upstream SSNbler main/develop and the fwapg
exports. Folded into task_plan.md the same day; each claim below was probed before acting on it (see
"Verified").

## Blocker
- **B1** The proposed parallel tests cannot fail once distances are exact: nodes are unique after the
  rounding dedup, so no to-end has two zero-distance nodes and `dbl_tonodes` is always empty. The
  700-line and split-pair tests fail before the fix and pass after it on the precision change alone.
  Fix: unit-test the chunk/combiner directly with duplicate node rows within a chunk and across the
  351/352 boundary of 701 rows, against the serial formula; mutation-check the offset; say in the PR
  the mechanism is unreachable with exact distances.
- **B2** Parallel workers load the installed SSNbler (`.packages`, and an exported function's
  namespace enclosure is serialised by name). Under `load_all()` the workers either miss `dist_xy` or
  test stale code. Fix: install the working tree before any parallel test, reprex B or
  restore-the-bug run.

## Gap
- **G1** `st_line_sample(sample = 1)` to-ends drift up to 2.3e-10 m from the last vertex (5 USKE,
  3 MSKE, 34 Skeena lines); with exact distances each reads 0 < d <= tolerance. Hidden today only by
  the rounding-bin merge and the `removed_nodes` suppression of Unsnapped errors; a coordinate on a
  bin boundary would split. Fix: take ends from vertices, as a separate commit.
- **G2** Rounding dedup bins are 10x snap_tolerance; `snap_tolerance = 0` gives `ndec = -1`, 10 m
  bins. Not a precision bug; mention upstream, do not change.
- **G3** Nothing checks `relationships.csv`, which the precision bug also corrupts via `rid_confl`.
- **G4** `split_matrix()` without `drop = FALSE` silently loses rownames on a 1-row last chunk in
  `get_pdist_rid`, so that edge's fromedge becomes NA (e.g. 249,501 edges).
- **G5** A helper test against `sqrt(rowSums((a-b)^2))` is circular, and a literal 0.001 offset at
  878000 is not exact in binary (relative error 4.75e-8 > testthat tolerance). Use binary-exact
  offsets, `expect_identical`, rectangular/data.frame/1-row inputs, multi-block with remainder.
- **G6** The pdist import is the roxygen tag at R/SSNbler-package.R:10; `ssnbler_reprex.R` still
  calls `pdist::pdist()` directly.
- **G7** Upstream tests only check `dim()` of `lines_to_lsn()` output; MF_streams (EPSG:5070, ~3e6 m)
  is where pdist error is largest. Snapshot its outputs before and diff after, both paths.
- **G8** `.combine = 'c'` would flatten a pair matrix; take offsets from real chunk sizes
  (701 -> 351/350, not 500/201); `sort(unique())` to match serial `which()`.
- **G9** Memory: serial keeps `node_dist` + `dist_matrix` + an `apply()` copy (~7.5 N^2 measured at
  USKE); a blocked helper filling a preallocated matrix lowers the peak; a single full `outer()`
  would need ~4 N^2 of temporaries.

## Ordering
- **O1** The "before" memory measurement belongs before the change: use runs.log 2026-10-10.
- **O2** Restore-the-bug after Phase 3, one defect at a time.
- **O3** Upstream `develop` is one commit ahead of main at 1.1.2.9000 with a dev NEWS header: branch
  from it, target it, ask the maintainer (CI runs on PRs to main).
- **O4** Install from the local clone while iterating; pin the SHA once.
- **O5** Validation section duplicated in task_plan.md.

## Assumption
- **A1** Keep the 3-line coordinates pinned (a 3 cm pair reads 0 at only ~63% of random BC Albers
  positions).
- **A2** Assert fresh exports still hold 239055049 and 141013301, or "0 errors" could mean they
  vanished.
- **A3** `get_pdist_rid`/`pdist_rid_confl` have no other chunk-local bug (global rows, rid
  colnames); only G4.
- **A4** The pairs design is equivalent to serial given G8.

## Scope
- **S1** Keep the PR to three commits (precision, offsets, drop); vertex ends optional/follow-up.
- **S2** Do not lift max.edges, do not change ndec; note `apply(simplify = FALSE)` needs R >= 4.1
  against `Depends: R >= 3.5`.

## Acceptance
- **AC1** Missing a `rid_confl` call site would still pass "0 node errors": add relationships checks.
- **AC2** No acceptance run exercises the parallel fix (B1); say so.
- **AC3** Print SSNbler version and RemoteSha in `ssnbler_check.R`.
- **AC4** Re-run Bulkley (parallel, clean before) and diff relationships against the existing output.
- **AC5** The shift test lacks `unlink(node_errors.gpkg)`; run it with no shift on existing exports.
- **AC6** Expected from the reviewer's simulation of the fixed serial logic: 0 errors, 1 outlet, and
  5/3/34 raw Unsnapped flags all suppressed. If the suppressed count differs, investigate.

## Verified (2026-10-11)
- O3: `upstream/develop` = d3918f1 "Updated development version number", 1.1.2.9000; fork branch
  recreated from it. Upstream workflow: R-CMD-check.yaml.
- O5: two `## Validation` headings; fixed.
- G1/A2: to-end drift 5 lines (USKE) and 3 (MSKE), max 2.328306e-10 m, from-ends 0;
  239055049 = 0.0161 m, 141013301 = 0.0293 m in the existing exports. The suppression is
  `R/lines_to_lsn.R:569` (Unsnapped errors at a `removed_nodes$new.pointid`).
- G6: `#' @importFrom pdist pdist` at R/SSNbler-package.R:10.
