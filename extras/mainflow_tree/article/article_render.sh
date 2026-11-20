#!/bin/bash
# Render the article to a self-contained mainflow_tree_area.html beside this
# script, from the committed extracts alone (no database). The page stays
# local: the HTML is gitignored.
#
#   ./article_render.sh
set -euo pipefail
cd "$(dirname "$0")" || exit 1

# The maps need gq's esri_satellite basemap (NewGraphEnvironment/gq#123).
GQ_PIN="NewGraphEnvironment/gq@02c6531"
Rscript --vanilla -e 'ok <- requireNamespace("gq", quietly = TRUE) &&
  "esri_satellite" %in% eval(formals(gq::gq_mapgl_basemap)$basemap); quit(status = !ok)' \
  || { echo "REFUSE: the installed gq has no esri_satellite basemap. Install it with:"
       echo "  Rscript -e 'pak::pak(\"$GQ_PIN\")'"; exit 1; }

rm -f mainflow_tree_area.html
env -u DATABASE_URL -u PGSERVER Rscript --vanilla -e \
  'rmarkdown::render("mainflow_tree_area.Rmd", output_file = "mainflow_tree_area.html", quiet = TRUE)'
[ -s mainflow_tree_area.html ] || { echo "REFUSE: no HTML written"; exit 1; }
echo "wrote $(pwd)/mainflow_tree_area.html ($(du -h mainflow_tree_area.html | cut -f1))"
