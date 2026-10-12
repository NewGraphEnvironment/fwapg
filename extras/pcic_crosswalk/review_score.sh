#!/bin/bash
set -euo pipefail

# Score a filled-in review GeoPackage (NewGraphEnvironment/fwapg#8): error rate
# per stratum with a 95% interval. Refuses a GeoPackage drawn from another
# sample, or one whose review layer has lost, gained or repeated a review_id.
#
#   ./review_score.sh <filled review.gpkg> [design csv, default review/sample_design.csv]
#
# Needs a database ($DATABASE_URL, temporary tables only) and GDAL.

PSQL="psql $DATABASE_URL -v ON_ERROR_STOP=1"
GPKG=$1
DESIGN=${2:-review/sample_design.csv}

[ -s "$GPKG" ] || { echo "no GeoPackage at $GPKG" >&2; exit 1; }
[ -s "$DESIGN" ] || { echo "no sample design at $DESIGN" >&2; exit 1; }
T=$(mktemp -d -t review_score.XXXXXX)
trap 'rm -rf "$T"' EXIT

# the GeoPackage names its design by the design file's md5. Read through GDAL,
# which also sees edits QGIS has left in a write-ahead log
ogr2ogr -f CSV "$T/sample.csv" "$GPKG" sample
got=$(sed -n 2p "$T/sample.csv" | tr -d '"\r')
want=$(md5sum < "$DESIGN" | cut -c1-32)
if [ "$got" != "$want" ]; then
  echo "refused: the GeoPackage's sample_id ($got) is not the md5 of $DESIGN ($want)" >&2
  exit 1
fi

ogr2ogr -f CSV "$T/review.csv" "$GPKG" -sql 'SELECT review_id, verdict, confidence, note FROM review'
case "$DESIGN$T" in *\'*) echo "a path with a single quote cannot be passed to \\copy" >&2; exit 1 ;; esac
$PSQL -qtXA -F '|' \
  -c "CREATE TEMPORARY TABLE design (review_id integer, subid integer, stratum text, drawn boolean)" \
  -c "\\copy design FROM '$DESIGN' WITH (FORMAT csv, HEADER)" \
  -c "CREATE TEMPORARY TABLE review (review_id integer, verdict text, confidence text, note text)" \
  -c "\\copy review FROM '$T/review.csv' WITH (FORMAT csv, HEADER)" \
  -f sql/review_score.sql
