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


## Errors Encountered

| Error | Resolution |
|-------|------------|
