# Check a subset of the main-flow tree with SSNbler's topology check (fwapg#2).
#
#   Rscript ssnbler_check.R <streams file> <lsn directory> [expected outlets]
#
# <streams file> is any file sf reads (GeoPackage, GeoJSON) holding tree segments
# as FWA delivers them, digitized from the downstream end; see README.md for the
# export. Every line is reversed (SSNbler wants lines digitized in the direction
# of flow), with no exceptions, and the landscape network is built in <lsn
# directory> with check_topology = TRUE. Prints the SSNbler build, the node classes
# and any node errors, and exits 1 if there is a node error, if an edge flows into
# two or the edge relationships do not number one per edge less the outlets, or if
# [expected outlets] is given and the network has a different number of outlets.
#
# With SSNBLER_AREA=1 in the environment and an upstream_area_ha column in the
# streams file (the tree's upstream area, fwapg#4), a clean network also gets
# additive function values from that area (afv_edges, then afv_sites on a fixed
# sample of points), with no overrides. The step prints one "area:" line and
# exits 6 if it fails: an edge with no area or none above zero, an additive
# function value outside (0, 1], an outlet edge whose value is not 1, or a test
# side channel whose share of its confluence is not small. Only that last check
# can tell a wrong area from a right one, and it runs only where the subset
# holds one of the three Skeena test side channels; the line says how many.
#
# SSNbler needs its parallel path at 46,340 lines or more. Below that it runs
# serially, with memory growing as the square of the lines (52 GB at 30,000).
# SSNbler 1.1.2 reports false errors at segments a few cm long, and on the
# parallel path puts the unsnapped flags on the wrong nodes (pet221/SSNbler#8,
# ssnbler_reprex.R, README.md); install the fixed fork the README names.

args <- commandArgs(trailingOnly = TRUE)
if (!length(args) %in% c(2, 3)) {
  stop("usage: Rscript ssnbler_check.R <streams file> <lsn directory> [expected outlets]")
}

# the build that ran: the version, and where it came from (owner/repo@commit for
# an install from GitHub, the repository (CRAN) for a repository install, the remote
# type pak recorded for anything else, or local)
d <- packageDescription("SSNbler")
src <- if (identical(d$RemoteType, "github")) {
  paste0(d$RemoteUsername, "/", d$RemoteRepo, "@", substr(d$RemoteSha, 1, 7))
} else if (!is.null(d$Repository)) d$Repository else if (!is.null(d$RemoteType)) d$RemoteType else "local"
cat("ssnbler:", d$Version, src, "\n")

streams <- sf::st_read(args[1], quiet = TRUE)
streams <- sf::st_zm(streams)
streams <- sf::st_cast(streams, "LINESTRING", warn = FALSE)
if (is.na(sf::st_crs(streams))) sf::st_crs(streams) <- 3005
sf::st_geometry(streams) <- sf::st_reverse(sf::st_geometry(streams))

# lines_to_lsn writes node_errors.gpkg only when it finds errors and never removes
# an old one, so a rerun into the same directory would read stale errors
unlink(file.path(args[2], "node_errors.gpkg"))

# SSNbler's parallel path starts a PSOCK cluster with makeCluster()'s defaults.
# Logging its workers to <lsn directory>.workers.log keeps their errors and puts
# that absolute path on their command lines, which is how ssnbler_check.sh tells
# this run's workers from any other R cluster on the machine.
lsn_abs <- if (startsWith(args[2], "/")) args[2] else file.path(getwd(), args[2])
parallel:::setDefaultClusterOptions(outfile = paste0(lsn_abs, ".workers.log"))

# snap_tolerance is the distance within which line ends join a node, and it sets
# the precision nodes are rounded to: one decimal place fewer than it has
# (lines_to_lsn: ndec <- get_decimals(snap_tolerance) - 1), so 0.001 rounds to
# 1 cm, the precision of qa_topology.sql (which joins ends in the same 1 cm cell
# rather than by distance), 0.01 to 0.1 m and the default 0 to 10 m.
# topo_tolerance changed nothing here (1 m and 1 cm gave the same errors).
#
# In 1.1.2 the distances came from pdist::pdist(), which works in single
# precision, so at BC Albers coordinates the 1 mm tolerance acted as several cm:
# the errors at 239055049 (1.6 cm, USKE) and 141013301 (2.9 cm, MSKE) were that,
# not the geometry. The fork computes them in double precision (pet221/SSNbler#8).
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
# The tree does not split, so no edge flows into two, and every edge but an outlet
# flows into one: a relationships table that disagrees joined ends it should not have
rel <- read.csv(file.path(args[2], "relationships.csv"))
n_split <- sum(duplicated(rel$fromedge))
cat("relationships:", nrow(rel), " expected:", nrow(streams) - n_outlets, " edges into two:", n_split, "\n")
cat("node errors:", n_errors, " outlets:", n_outlets, "\n")
if (n_errors > 0 || n_split > 0 || nrow(rel) != nrow(streams) - n_outlets) quit(status = 1)
if (length(args) == 3 && n_outlets != as.integer(args[3])) quit(status = 1)

if (!identical(Sys.getenv("SSNBLER_AREA"), "1")) quit(status = 0)

# Any positive areas give additive function values in (0, 1] and 1 at the
# outlets, so those limits alone cannot tell a wrong area from a right one. What
# can: where a test side channel's mouth meets the Skeena, its share of the
# confluence (segment proportional influence) is the tributary's area over the
# river's, a few percent. With the watershed lookup's area, which gives a side
# channel its river's area, it is about a half. The mouth segments of 360216952,
# 360222216 and 360237491, checked where the subset holds them.
side_channel_mouths <- c(123041439, 87082084, 87078272)

area <- tryCatch({
  if (!"upstream_area_ha" %in% names(streams)) stop("the streams file has no upstream_area_ha column")
  edges <- sf::st_read(file.path(args[2], "edges.gpkg"), quiet = TRUE)
  # without the ids the side-channel check below would hold no edge and say nothing
  if (!"linear_feature_id" %in% names(edges)) stop("the edges have no linear_feature_id column")
  a <- edges$upstream_area_ha
  if (anyNA(a) || any(!is.finite(a)) || any(a <= 0)) {
    stop(sum(is.na(a) | !is.finite(a) | a <= 0), " edges have no area above zero")
  }
  edges <- SSNbler::afv_edges(
    edges,
    lsn_path = args[2],
    infl_col = "upstream_area_ha",
    segpi_col = "areaPI",
    afv_col = "afvArea",
    save_local = FALSE,
    overwrite = TRUE
  )
  afv <- edges$afvArea
  if (nrow(edges) != nrow(streams) || anyNA(afv) || any(afv <= 0 | afv > 1)) {
    stop("additive function values outside (0, 1] on ", sum(is.na(afv) | afv <= 0 | afv > 1), " edges")
  }
  # an outlet is an edge that flows into none
  at_outlet <- !edges$rid %in% rel$fromedge
  if (sum(at_outlet) != n_outlets || any(abs(afv[at_outlet] - 1) > 1e-9)) {
    stop("an outlet edge has an additive function value other than 1")
  }
  held <- edges$linear_feature_id %in% side_channel_mouths
  if (any(edges$areaPI[held] > 0.2)) {
    stop("a test side channel carries ", round(max(edges$areaPI[held]), 3), " of its confluence")
  }
  # sites: the midpoint of up to 200 edges, evenly spaced through the edge table
  pick <- unique(round(seq(1, nrow(edges), length.out = min(nrow(edges), 200))))
  sites <- sf::st_sf(
    site_id = pick,
    geometry = sf::st_line_sample(sf::st_geometry(edges)[pick], sample = 0.5)
  )
  sites <- sf::st_cast(sites, "POINT", warn = FALSE)
  sites <- SSNbler::sites_to_lsn(
    sites,
    edges,
    snap_tolerance = 1,
    save_local = FALSE,
    lsn_path = args[2],
    overwrite = TRUE,
    verbose = FALSE
  )
  sites <- SSNbler::afv_sites(list(obs = sites), edges, afv_col = "afvArea", save_local = FALSE)$obs
  if (nrow(sites) != length(pick) || anyNA(sites$afvArea) || any(sites$afvArea <= 0 | sites$afvArea > 1)) {
    stop("additive function values missing or outside (0, 1] at the sites")
  }
  # a subset that holds none of the test side channels has only the limits above
  sprintf(
    "area: ok  afv: %.3g to %.3g  sites: %d  side channels: %d (%s)",
    min(afv), max(afv), nrow(sites), sum(held),
    if (any(held)) paste("largest share", format(round(max(edges$areaPI[held]), 4))) else "none in this subset, not checked"
  )
}, error = function(e) paste("area: failed,", conditionMessage(e)))
cat(area, "\n")
if (startsWith(area, "area: failed")) quit(status = 6)
