# Findings — Fix SSNbler's false topology errors on a fork, PR upstream, re-run the SSNbler check (#16)

## Issue context

SSNbler 1.1.2 reports false node errors on FWA data (pet221/SSNbler#8). Fix it on a fork, offer the fix upstream as a PR with tests, and re-run `extras/mainflow_tree/ssnbler_check.sh` against the fixed version. Needed before SSN2 modelling on the main-flow tree, which builds its networks with SSNbler.

## The two defects

Reproduced with synthetic lines by `extras/mainflow_tree/ssnbler_reprex.R`; details in `research/fwa_mainflow_tree.md`.

1. **Precision.** `pdist_node_coords()` and the serial branch of `lines_to_lsn()` call `pdist::pdist()` on raw coordinates. At BC Albers magnitudes (~10⁶ m) it returns 0 for points up to ~7 cm apart (~4 mm error at 10⁵ m). A segment a few cm long reads as 2 Unsnapped Node + 2 Downstream Divergence. Fix: subtract a common origin from both matrices before every `pdist()` call. Check every call site, including `get_pdist_rid()` and the `from_xy`/`to_xy` call that builds `rid_confl`.
2. **Parallel path.** In `get_pdist_nodes()`, each chunk's `unsnapped_tonodes` are row numbers within the chunk, applied by `lines_to_lsn()` to the whole node vector with no offset. `dbl_tonodes` (`colSums(dist == 0) > 1`) is also counted within a chunk, so a pair split across chunks is missed. Fix: return each chunk's per-column zero counts, sum them across chunks, and compute `unsnapped_tonodes` as global rows. This only fires through (1): the reprex is clean on both paths at coordinates up to 10⁵ m.

Seen in our runs (2026-10, #13): USKE and MSKE each report 4 false errors at 239055049 (1.6 cm) and 141013301 (2.9 cm). The whole Skeena flags two ZYMO nodes, which are MSKE's segment ends (rows 462/463 of chunk 376) applied to global rows 462/463. USKE's two ends fall in chunks 348 and 360 and are not flagged at all.

## Steps

- [ ] Fork `pet221/SSNbler` to NewGraphEnvironment and branch it
- [ ] Fix (1) and (2)
- [ ] Add testthat cases built from the reprex: 3 lines at BC Albers coordinates come back clean, and parallel (2 cores, 700 lines) matches serial
- [ ] `R CMD check`
- [ ] **Acceptance test.** Install the fork branch and re-run `ssnbler_check.sh`: USKE and MSKE on the serial path, then the whole Skeena on the parallel path. Expect 0 node errors in all three, and 1 outlet for the Skeena. Also re-run the shift test below, which should now report 0 with no shift. If anything is still flagged, fix it and repeat. The upstream PR waits for this.
- [ ] Open the PR upstream, referencing pet221/SSNbler#8. This happens only after the acceptance test passes, and only with approval.
- [ ] fwapg: re-run results in the main-flow README and `research/fwa_mainflow_tree.md`; README installs SSNbler from the fork at a pinned commit. Switching back to CRAN is a separate issue, filed once upstream releases a fix.


## Evidence: the shift test

The README and research claim that USKE/MSKE errors disappear near the origin rests on this script (2026-10-10, SSNbler 1.1.2), run on each group's export from `ssnbler_check.sh` (`data/ssnbler/grp_skeena_{USKE,MSKE}.gpkg`). With an exact integer offset, USKE went from 4 errors to 0 and MSKE from 4 to 1. With a non-integer bounding-box corner, MSKE went to 0 and USKE to 1. Re-run it against the fixed fork, where both should be 0 without any shift.

```r
args <- commandArgs(TRUE)  # gpkg, lsn dir
s <- sf::st_read(args[1], quiet = TRUE)
s <- sf::st_cast(sf::st_zm(s), "LINESTRING", warn = FALSE)
sf::st_geometry(s) <- sf::st_reverse(sf::st_geometry(s))
off <- c(800000, 1200000)  # exact: every x in [400000, 1600000], y in [600000, 2400000]
g <- sf::st_geometry(s) - off   # same lines, coordinates near the origin
s <- sf::st_set_geometry(s, sf::st_sfc(g, crs = 3005))
lsn <- SSNbler::lines_to_lsn(s, lsn_path = args[2], check_topology = TRUE, snap_tolerance = 0.001,
  topo_tolerance = 1, overwrite = TRUE, use_parallel = FALSE, verbose = FALSE)
f <- file.path(args[2], "node_errors.gpkg")
cat("lines:", nrow(s), " node errors:", if (file.exists(f)) nrow(sf::st_read(f, quiet = TRUE)) else 0, "\n")
```



## Plan-mode exploration (2026-10-10)

**What exploration found**
- pdist() is called in 5 places: `lines_to_lsn.R` L349 (`pdist(from_xy, to_xy)`, rid_confl, serial) and L392–393 (`nodes_vs_from`, `nodes_vs_to`, serial topology), `pdist_node_coords.R` (parallel topology) and `pdist_rid_confl.R` (parallel rid_confl). The other `grep pdist` hits are `updist`. `get_rid_confl.R` already computes distances as differences, but nothing calls it.
- **I measured pdist's error (2026-10-10, pdist 1.2.1).** It grows in proportion to coordinate size: 0.9 mm at 10⁴ m, 9 mm at 10⁵, 1.6 cm at 2×10⁵, 6.4 cm at 10⁶. Identical points still read exactly 0. An origin shift therefore only shrinks the error to the size of the data's own extent, and the Skeena is about 4×10⁵ m across. **You chose exact distances** over the origin shift that the issue body prescribes. The issue body gets edited to match.
- **The parallel path.** `pdist_node_coords()` returns `unsnapped_tonodes` as row numbers within its chunk, and `dbl_tonodes` counts duplicates within the chunk only. `get_pdist_nodes()` concatenates them with no offset.
- `split_matrix()` uses `mat[a:b, ]` with no `drop = FALSE`, so a 1-row chunk turns into a vector. That is a latent bug in the code path being changed, so it gets fixed too.
- fwapg's files: `extras/mainflow_tree/{ssnbler_check.R, ssnbler_check.sh, ssnbler_reprex.R, README.md}` and `research/fwa_mainflow_tree.md` (L3, L33–38). The per-group exports for the acceptance test are already in `extras/mainflow_tree/data/ssnbler/`.

**Where the work happens.** The PWF and the issue live in fwapg, on branch `16-fix-ssnbler-s-false-topology-errors-on-a` off `newgraph`, with the PR `--base newgraph`. The SSNbler code lives in a new fork, `NewGraphEnvironment/SSNbler`, cloned to `~/Projects/repo/SSNbler`, on branch `fix-pdist-precision-parallel-unsnapped`.


## Phase 1 baseline (2026-10-11, fork at upstream 65eaf20)

`NewGraphEnvironment` is a user account, not an org, so `gh repo fork --org` fails (HTTP 422); the
fork is `gh repo fork pet221/SSNbler` as that user. Clone: `~/Projects/repo/SSNbler`, remotes `origin`
(fork) and `upstream` (pet221), branch `fix-pdist-precision-parallel-unsnapped`.

- `devtools::test()`: 157 pass, 0 fail, 0 skip (4 s).
- `ssnbler_reprex.R` against `load_all()` of the clone, unchanged from 1.1.2 on CRAN:
  - A, near origin: none. A, BC Albers: Unsnapped Node and Downstream Divergence at x=10.000 and 10.030.
  - B serial: the same pair at x=6490.000/6490.030. B parallel: Unsnapped Node at x=2980/2990 (rows
    149/150 of chunk 2 applied as global rows 149/150), Downstream Divergence at 6490.000/6490.030.

## With exact distances, `dbl_tonodes` cannot fire through `lines_to_lsn()`

`dbl_tonodes` is a to-end at distance exactly 0 from more than one node. Nodes are deduplicated by
rounded coordinates before the check, so two kept nodes never share coordinates, and an exact distance
of 0 means identical coordinates. It fired in 1.1.2 only through pdist's false zeros. The parallel
fix (2) is still made, and is tested by calling `get_pdist_nodes()` directly with duplicate node
rows placed in one chunk and across two, against the serial formula.

Parallel workers load the **installed** SSNbler (`.packages = "SSNbler"`); a function sent with
`.export` keeps its namespace as enclosure, so it resolves helpers against the installed version.
Parallel tests therefore exercise the installed package: install the branch before `devtools::test()`
(R CMD check installs it anyway).

## Phase 2-3: the fork changes (2026-10-11)

Fork commits on `fix-pdist-precision-parallel-unsnapped` (from upstream `develop` d3918f1):
9d759a9 tests, 5a7b208 `dist_xy()` replaces all 5 `pdist()` calls and drops pdist, 20f7021 parallel
zero pairs + `combine_node_chunks()`, 5a072ef `split_matrix(drop = FALSE)`.

- New tests on unmodified code: 10 failures/errors. The 3-line chain at BC Albers also writes a wrong
  `relationships.csv` (review G3 confirmed: `rid_confl` joins ends 3 cm apart).
- After the fix, branch installed: `devtools::test()` 188 pass, 0 fail (157 upstream + 31 new).
- MF_streams (EPSG:5070) before/after on both paths: `relationships.csv`, `noderelationships.csv`,
  `nodexy.csv` and node attributes byte-identical; 0 errors, Confluence 52 / Outlet 2 / Pseudonode
  57 / Source 54.
- Restore-the-bug, each mutant installed to its own library with `R_LIBS` so the PSOCK workers run it:
  `dist_xy` -> pdist: 8 failures, including the parallel test (so the workers ran the mutant); no
  chunk offset: the combiner test; no `drop = FALSE`: the `split_matrix` test.
- `split_matrix()` 1-row chunk, probed: 3 edges in 2 chunks give `rid_confl` names `"1","2",""`, so
  `as.integer("")` makes that edge's `fromedge` NA. Fixed: `"1","2","3"`.

## The `st_line_sample()` end-point drift: measured, not changed

`st_line_sample(sample = 1)` lands 1 ulp (1.16e-10 or 2.33e-10 m) off the last vertex on long lines
(5 USKE lines with 61-143 vertices; from-ends never drift). With exact distances, such an end reads
0 < d <= tolerance from the downstream line's start. That is harmless while both round into the same
1 cm bin: the nodes merge and `lines_to_lsn.R:569` drops Unsnapped errors at merged nodes. FWA
coordinates are whole mm, so a coordinate ending in 5 mm sits on a bin edge, and a 1-ulp drift the
right way would split the nodes and flag both. No crossing in 20,000 random 4-vertex lines (no
drift at all) or in 1,500 translations of the five real drifting lines placed on a bin edge. It is
not reproducible, so it stays out of the PR and is mentioned there; if a run ever flags a pair of
nodes ~1e-10 m apart, taking ends from `st_coordinates()` is the fix.

## Phase 4: R CMD check (2026-10-11)

`rcmdcheck(args = c("--no-manual", "--as-cran"))`, R 4.5.2 aarch64: 0 errors, 0 warnings, 1 NOTE
("Version contains large components (1.1.2.9000)", the dev version upstream set). Tests inside the
check: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 188 ]` with `NOT_CRAN=true` (so the parallel test ran).

The first attempt reported `ERRORS 0 WARNINGS 0 NOTES 0` while the check had **halted** at "checking
CRAN incoming feasibility" (`archive.rds` timeout, "Execution halted"): rcmdcheck counts the
findings it parsed, and an aborted check has none. Re-run with `_R_CHECK_CRAN_INCOMING_REMOTE_=false`.
Read the log's `* DONE` / `Status:` line, not the counts.

## /code-check on the fork branch (2026-10-11, 3 rounds, `review-round{1,2,3}.md`)

| Round | Findings | Fixed | Accepted | Inside previous fix? |
|-------|----------|-------|----------|----------------------|
| 1 | 0 (Clean; noted pdist looks single precision) | wording: the mechanism was wrong (cancellation -> single precision) | 2 pre-existing, outside the diff | — |
| 2 | 3 wording (figures true only at one magnitude; "1 cm at 2e5" was 1.6; "500-node" is a cap) | 3 | 0 | **y** (the round-1 rewording) |
| 3 | 7 wording, one mechanism | all, by removing range claims | 0 | **y** |

Code was clean in all three rounds. **pdist rounds each coordinate to float on its own
(`as.single()` in `pdist.R`, `float` in `pdist.c`)**: a pair reads 0 exactly when x and y each round
to the same float, so whether a given pair reads 0 is a coincidence of position, not a threshold. Every
wrong figure had been a value seen at one configuration (one magnitude, one axis, one position, one
network size) stated as a constant. Ended by enumeration: the 13 factual claims in NEWS, code and test
comments and the four commit messages, each matched to a computation or measurement (float spacing
2^(e-23): 0.0625 at 1e6, 0.125 at 1,261,000; "five pdist() calls" by `git grep`; "up to 500" over
n <= 3e6; "every chunk after the first" reproduced on base, 701-node fixture -> 249 250; the NA
`fromedge` probed). The NEWS entry now states the mechanism and says "can", with no ranges.

Pushed: NewGraphEnvironment/SSNbler `fix-pdist-precision-parallel-unsnapped` at **37ca338**
(commits 8818f36 tests, eb66682 precision, ca0def8 offsets, 37ca338 drop). The branch was rewritten
twice before the push (wording only; code and tests byte-identical, checked with `git diff --quiet`).

## Phase 5: acceptance (2026-10-11)

Database: a local fwapg holding the main-flow tree (`DATABASE_URL` set to a pg service name).

| run | build | lines | node errors | outlets | relationships ok | peak GB | min | 1.1.2 (2026-10-10) |
|---|---|---|---|---|---|---|---|---|
| USKE serial | local 8505fb5 tree | 21,655 | 0 | 1 | yes | 18.0 | 2 | 4 errors, 28.0 GB |
| MSKE serial | local | 24,732 | 0 | 1 | yes | 24.0 | 2 | 4 errors, 37.0 GB |
| Bulkley parallel | local | 52,293 | 0 | 1 | yes; csvs byte-identical to 1.1.2 | 3.8 | 3 | 0, 3.5 GB |
| Skeena parallel | local 8505fb5 (R code = 37ca338) | 261,764 | 0 | 1 | 261,763, none into two | 10.9 | 54 | 6 errors, 19.9 GB, 35 min |
| USKE serial | `pak` 37ca338 | 21,655 | 0 | 1 | yes | 17.0 | 2 | |
| MSKE serial | `pak` 37ca338 | 24,732 | 0 | 1 | yes | 28.0 | 2 | |

- Exports still hold 239055049 (0.0161 m) and 141013301 (0.0293 m).
- No-shift test (issue's script, `off <- c(0, 0)`, stale node_errors removed) on both exports: 0 and 0.
- `ssnbler_reprex.R`: clean on all four checks; it still prints pdist's 0 for 3 cm.
- **Slower on the parallel path:** 54 min for the Skeena against 35 on 1.1.2. `dist_xy()` is R
  (`outer()` per block) where pdist was C. Memory roughly halved there; on the serial groups peak fell
  10-13 GB. MSKE's peak was 24 GB on one run and 28 on the next, so a few GB is sampling variation.
- The Skeena ran on the build one wording-only rewrite before 37ca338: `git diff 8505fb5 37ca338` is
  NEWS.md and the `dist_xy.R` header comment only.
- `pak` installing 37ca338 also updated 1 and added 3 dependency packages in the user library.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| rcmdcheck `ERRORS 0 WARNINGS 0 NOTES 0` on a check that halted (CRAN `archive.rds` timeout) | `_R_CHECK_CRAN_INCOMING_REMOTE_=false`; trust `Status:` in 00check.log |
| `gh repo fork --org NewGraphEnvironment`: HTTP 422, login for a user account | Fork without `--org` (authenticated as that user) |
