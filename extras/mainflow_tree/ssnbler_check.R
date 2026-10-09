# Check a subset of the main-flow tree with SSNbler's topology check (fwapg#2).
#
#   Rscript ssnbler_check.R <streams file> <lsn directory> [expected outlets]
#
# <streams file> is any file sf reads (GeoPackage, GeoJSON) holding tree segments
# as FWA delivers them, digitized from the downstream end; see README.md for the
# export. Every line is reversed (SSNbler wants lines digitized in the direction
# of flow), with no exceptions, and the landscape network is built in <lsn
# directory> with check_topology = TRUE. Prints the node classes and any node
# errors, and exits 1 if there is a node error, or if [expected outlets] is given
# and the network has a different number of outlets.
#
# SSNbler needs its parallel path at 46,340 lines or more, and each worker holds
# about 2 GB on a 160,000-line subset; a watershed group at a time stays under
# the limit and runs serially.

args <- commandArgs(trailingOnly = TRUE)
if (!length(args) %in% c(2, 3)) {
  stop("usage: Rscript ssnbler_check.R <streams file> <lsn directory> [expected outlets]")
}

streams <- sf::st_read(args[1], quiet = TRUE)
streams <- sf::st_zm(streams)
streams <- sf::st_cast(streams, "LINESTRING", warn = FALSE)
if (is.na(sf::st_crs(streams))) sf::st_crs(streams) <- 3005
sf::st_geometry(streams) <- sf::st_reverse(sf::st_geometry(streams))

# lines_to_lsn writes node_errors.gpkg only when it finds errors and never removes
# an old one, so a rerun into the same directory would read stale errors
unlink(file.path(args[2], "node_errors.gpkg"))

# snap_tolerance is the distance within which line ends join a node, and it sets
# the precision nodes are rounded to: one decimal place fewer than it has
# (lines_to_lsn: ndec <- get_decimals(snap_tolerance) - 1), so 0.001 rounds to
# 1 cm, as qa_topology.sql does, 0.01 to 0.1 m and the default 0 to 10 m.
# topo_tolerance flags nodes closer than it that are not joined.
#
# Two spots still report errors, each a main-flow segment a few cm long whose
# geometry is a plain chain: 239055049 (1.6 cm, USKE) and 141013301 (2.9 cm,
# MSKE). At snap_tolerance 0.01 its two ends round to one node (a "Downstream
# Divergence"); at 0.001 they stay apart but are flagged as an "Unsnapped Node"
# and a divergence, with topo_tolerance 1 m and 1 cm alike.
lsn <- SSNbler::lines_to_lsn(
  streams,
  lsn_path = args[2],
  check_topology = TRUE,
  snap_tolerance = 0.001,
  topo_tolerance = 1,
  overwrite = TRUE,
  use_parallel = nrow(streams) >= 46340,
  no_cores = 4,
  verbose = FALSE
)

nodes <- sf::st_read(file.path(args[2], "nodes.gpkg"), quiet = TRUE)
cat("lines:", nrow(streams), "\n")
print(table(nodecat = nodes$nodecat, useNA = "ifany"))

errors_file <- file.path(args[2], "node_errors.gpkg")
n_errors <- 0
if (file.exists(errors_file)) {
  errors <- sf::st_read(errors_file, quiet = TRUE)
  n_errors <- nrow(errors)
  print(table(error = errors$error, nodecat = errors$nodecat))
}
n_outlets <- sum(nodes$nodecat == "Outlet")
cat("node errors:", n_errors, " outlets:", n_outlets, "\n")
if (n_errors > 0) quit(status = 1)
if (length(args) == 3 && n_outlets != as.integer(args[3])) quit(status = 1)
