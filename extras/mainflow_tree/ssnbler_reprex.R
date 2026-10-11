# SSNbler 1.1.2: topology check vs coordinate magnitude, serial vs parallel
# (pet221/SSNbler#8). Synthetic lines only, no database:
#
#   Rscript ssnbler_reprex.R
#
# A: pdist::pdist() computes in single precision, so at BC Albers coordinates it
# returns 0 for points a few cm apart, and a 3 cm line reads as an unsnapped node
# and a divergence. B: on the parallel path the unsnapped flags are chunk-local row
# numbers, applied to the whole node list, so they land on the wrong nodes. The
# NewGraphEnvironment/SSNbler fork (README.md) fixes both: every check is clean.
library(sf)

# A straight chain of n lines, 10 m each, digitized downstream (east), with line k
# replaced by a 3 cm line. Every end meets the next start exactly: no topology errors.
chain <- function(n, k, x0, y0) {
  xs <- x0 + c(seq(0, by = 10, length.out = k), 10 * (k - 1) + 0.03 + seq(0, by = 10, length.out = n - k + 1))
  l <- lapply(seq_len(n), function(i) st_linestring(cbind(xs[i + 0:1], y0)))
  st_sf(id = seq_len(n), geometry = st_sfc(l, crs = 3005))
}
check <- function(lines, parallel, label) {
  d <- file.path(tempdir(), paste0("lsn_", gsub("[^A-Za-z0-9]+", "_", label)))
  SSNbler::lines_to_lsn(lines, lsn_path = d, check_topology = TRUE, snap_tolerance = 0.001,
    topo_tolerance = 1, overwrite = TRUE, use_parallel = parallel, no_cores = 2, verbose = FALSE)
  f <- file.path(d, "node_errors.gpkg")
  e <- if (file.exists(f)) st_read(f, quiet = TRUE) else NULL
  cat(sprintf("%-34s errors: %s\n", label,
    if (is.null(e)) "none" else paste(sprintf("%s at x=%.3f", e$error, st_coordinates(e)[, 1] - min(st_coordinates(lines)[, 1])), collapse = "; ")))
}

# A. Precision: 3 lines, the middle one 3 cm long
check(chain(3, 2, 0, 0),             FALSE, "A: 3 lines near the origin")
check(chain(3, 2, 878000, 1261000),  FALSE, "A: 3 lines at BC Albers coords")
# pdist is no longer an SSNbler dependency once fixed, so it may not be installed
if (requireNamespace("pdist", quietly = TRUE)) {
  cat("   pdist of two points 3 cm apart at BC Albers coords:",
      as.matrix(pdist::pdist(matrix(c(878000, 1261000), 1), matrix(c(878000.03, 1261000), 1))), "\n")
}

# B. Chunks: 700 lines (701 nodes, split into two chunks), the 3 cm line at 650 (chunk 2)
big <- chain(700, 650, 878000, 1261000)
check(big, FALSE, "B: 700 lines, serial")
check(big, TRUE,  "B: 700 lines, parallel")
