# fwapg#4 Phase 5: a control for the SSNbler area step. On a landscape network
# ssnbler_check.sh already built with SSNBLER_AREA=1, swap the tree's area for
# the watershed lookup's and compute the segment proportional influence of the
# test side channels' mouth edges again. The lookup gives a side channel its
# river's area, so the share should be about a half, where the tree's area gives
# a few percent, and the step's limit of 0.2 fails it.
#
#   Rscript 09_ssnbler_lookup_control.R <lsn directory> <lookup csv>
#
# <lookup csv>: linear_feature_id, lookup_area_ha for the subset's segments
# (psql \copy from fwa_streams_watersheds_lut joined to fwa_watersheds_upstream_area).

args <- commandArgs(trailingOnly = TRUE)
edges <- sf::st_read(file.path(args[1], "edges.gpkg"), quiet = TRUE)
lookup <- read.csv(args[2])
tree_area <- edges$upstream_area_ha
m <- match(edges$linear_feature_id, lookup$linear_feature_id)
# a segment with no lookup row keeps the tree's area, so afv_edges can run
edges$upstream_area_ha <- ifelse(is.na(lookup$lookup_area_ha[m]), tree_area, lookup$lookup_area_ha[m])
mouths <- c(123043588, 87082084, 87078272)
pi_of <- function(e) {
  e <- SSNbler::afv_edges(e, lsn_path = args[1], infl_col = "upstream_area_ha",
    segpi_col = "areaPI", afv_col = "afvArea", save_local = FALSE, overwrite = TRUE)
  e$areaPI[match(mouths, e$linear_feature_id)]
}
with_lookup <- pi_of(edges)
edges$upstream_area_ha <- tree_area
with_tree <- pi_of(edges)
print(data.frame(linear_feature_id = mouths, share_with_tree_area = round(with_tree, 4), share_with_lookup_area = round(with_lookup, 4)))
cat("the step's limit (0.2) fails the lookup's area:", any(with_lookup > 0.2, na.rm = TRUE), "\n")
