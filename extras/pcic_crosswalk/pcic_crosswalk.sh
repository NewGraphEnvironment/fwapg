#!/bin/bash
set -euxo pipefail

# Crosswalk PCIC hydromosaic sub-basin outlets to FWA streams and derive
# monthly flow per FWA stream segment. See README.md.

PSQL="psql $DATABASE_URL -v ON_ERROR_STOP=1"
PCIC=https://beehive.pacificclimate.org
PAGE=1000      # features per bbox-server page
BATCH=500      # outlets per bulk timeseries request
YEARS=1951/2012  # PNWNAmet run is 1950-2012; day 1 is a model start-up artefact, drop 1950

mkdir -p data/rivers data/lakes data/series data/monthly

# ----------
# 1. PCIC network (rivers and lakes), cached page by page
# ----------
fetch_collection() {
  local coll=$1 n offset f
  n=$(curl -sf --retry 5 "$PCIC/bbox-server/collections/$coll/items.json?limit=1" | jq '.numberMatched')
  for ((offset = 0; offset < n; offset += PAGE)); do
    f=data/$coll/${coll}_$(printf '%06d' $offset).geojson
    if [ ! -s "$f" ]; then
      # feature id is the PCIC subid; move it into the properties so ogr2ogr keeps it
      curl -sf --retry 5 "$PCIC/bbox-server/collections/$coll/items.json?limit=$PAGE&offset=$offset" \
        | jq -c '{type, features: (.features | map(.properties.subid = (.id | tonumber)))}' > "$f.tmp"
      mv "$f.tmp" "$f"
    fi
  done
}
fetch_collection rivers
fetch_collection lakes

for coll in rivers lakes; do
  jq -c -s '{type: "FeatureCollection", features: (map(.features) | add)}' data/$coll/${coll}_*.geojson > data/$coll.geojson
  ogr2ogr -f PostgreSQL "PG:$DATABASE_URL" data/$coll.geojson \
    -nln fwapg.pcic_$coll -overwrite -a_srs EPSG:3005 -nlt PROMOTE_TO_MULTI \
    -lco GEOMETRY_NAME=geom -select subid,dowsubid
done

# outlet point per sub-basin, flow direction, root and depth of each tree
$PSQL -f sql/pcic_crosswalk00_outlets.sql

# ----------
# 2. PNWNAmet streamflow, reduced to monthly climatology per outlet
# ----------
# The bulk endpoint returns daily NetCDF for many outlets, but only from one
# source file per request (one domain); a mixed request returns 422. Batches are
# drawn per tree, ordered by root, and halved on 422 until each part is
# single-domain. An outlet that returns 422 on its own has no series and is
# logged to data/series/missing.txt. A batch of more than 50 outlets that keeps
# failing otherwise (502s and truncated files under load) is halved too; below
# that, the failure stops the run (exit 255 stops xargs).
#
# Each batch leaves data/monthly/<batch>.csv (empty only for a missing outlet) or
# a <batch>.split marker, so a re-run resumes where it stopped. Remove
# data/monthly and data/series to fetch again.
fetch_batch() {
  local ids=$1 out=data/monthly/$(basename "$1" .txt).csv nc code n try outlets
  [ -e "$out" ] && return 0
  n=$(wc -l < "$ids")
  if [ ! -e "${ids%.txt}.split" ]; then
    nc=${ids%.txt}.nc
    for try in 1 2 3; do
      code=$(jq -R -s -c \
          '{subids: (split("\n") | map(select(length > 0))), model: "PNWNAmet", scenario: "historical", variable: "streamflow", format: "netcdf"}' "$ids" \
        | curl -s -L --retry 5 -m 1800 -X POST "$PCIC/hydromosaic/bulk-downloads" \
            -H 'Content-Type: application/json' -d @- -o "$nc" -w '%{http_code}') || code=000
      [ "$code" = 422 ] && break
      [ "$code" = 200 ] && ncdump -h "$nc" > /dev/null 2>&1 && break
      code=failed
      sleep $((try * 30))
    done
    if [ "$code" = 200 ]; then
      # monthly mean of daily flow; outlet order is the file's basin_name order.
      # This runs under xargs without set -e, so every step is checked.
      outlets=$(ncdump -v basin_name "$nc" | sed -n '/basin_name =/,/;/p' | grep -oE '"[^"]+"' | tr -d '"' | paste -sd, -) \
        && [ -n "$outlets" ] \
        && cdo -s -O ymonmean -selyear,"$YEARS" "$nc" "${nc%.nc}_mon.nc" \
        && ncdump -v streamflow "${nc%.nc}_mon.nc" > "${nc%.nc}_mon.cdl" \
        || { echo "reducing $nc failed" >&2; return 255; }
      # ncdump prints the (month, outlet) array row-major; "_" is a fill value
      awk -v ids="$outlets" '
        BEGIN { n = split(ids, sid, ",") }
        /^ streamflow =/ { on = 1; next }
        on {
          last = /;/
          gsub(/[;,]/, " ")
          for (i = 1; i <= NF; i++) {
            k++
            if ($i != "_") print sid[(k - 1) % n + 1] "," int((k - 1) / n) + 1 "," $i
          }
          if (last) exit
        }
        END { if (k != 12 * n) exit 1 }' "${nc%.nc}_mon.cdl" > "$out.tmp" \
        || { echo "unexpected monthly array in ${nc%.nc}_mon.cdl" >&2; return 255; }
      mv "$out.tmp" "$out"
      rm -f "$nc" "${nc%.nc}_mon.nc" "${nc%.nc}_mon.cdl"
      return 0
    fi
    rm -f "$nc"
    if [ "$code" = 422 ] && [ "$n" -eq 1 ]; then
      cat "$ids" >> data/series/missing.txt
      : > "$out"
      return 0
    fi
    if [ "$code" != 422 ] && [ "$n" -le 50 ]; then
      echo "bulk download failed for $ids" >&2
      return 255
    fi
    head -n $((n / 2)) "$ids" > "${ids%.txt}a.txt"
    tail -n +$((n / 2 + 1)) "$ids" > "${ids%.txt}b.txt"
    touch "${ids%.txt}.split"
  fi
  fetch_batch "${ids%.txt}a.txt" && fetch_batch "${ids%.txt}b.txt"
}
export -f fetch_batch
export PCIC YEARS

rm -f data/series/batch_???_????.txt
$PSQL -tXA -F ' ' -c "SELECT root_subid / 1000000, subid FROM fwapg.pcic_outlets ORDER BY root_subid / 1000000, root_subid, subid" \
  | awk -v b=$BATCH '{ if ($1 != g || ++n > b) { g = $1; n = 1; k++ } print $2 > sprintf("data/series/batch_%03d_%04d.txt", $1, k) }'
ls data/series/batch_*.txt | grep -E '_[0-9]{4}\.txt$' | xargs -P 3 -I {} bash -c 'fetch_batch "$1"' _ {}

$PSQL -c "DROP TABLE IF EXISTS fwapg.pcic_outlet_monthly"
$PSQL -c "CREATE TABLE fwapg.pcic_outlet_monthly (subid integer, month integer, q_m3s double precision, PRIMARY KEY (subid, month))"
cat data/monthly/*.csv | $PSQL -c "\copy fwapg.pcic_outlet_monthly FROM STDIN WITH (FORMAT csv)"

# ----------
# 3. Snap outlets to the FWA and place them so PCIC's routing chain holds
# ----------
# downstream path of every FWA blue line, used for every position comparison
../blue_line_paths/blue_line_paths.sh
$PSQL -v tolerance=150 -v num_features=5 -f sql/pcic_crosswalk02_candidates.sql
$PSQL -f sql/pcic_crosswalk03_prepare.sql
# place, then demote outlets that misplaced the chain above them, until stable
for round in $(seq 1 10); do
  $PSQL -f sql/pcic_crosswalk04_select.sql
  n=$($PSQL -q -tXA -v round=$round -f sql/pcic_crosswalk05_demote.sql)
  [ "$n" -eq 0 ] && break
  # demotions from the last round have not been applied to a placement
  [ "$round" -lt 10 ] || { echo "placement did not converge in 10 rounds" >&2; exit 1; }
done

# ----------
# 4. Monthly flow per FWA stream segment
# ----------
$PSQL -f sql/pcic_crosswalk06_subbasins.sql
$PSQL -c "DROP TABLE IF EXISTS whse_basemapping.fwa_stream_networks_discharge_monthly"
$PSQL -c "CREATE TABLE whse_basemapping.fwa_stream_networks_discharge_monthly (
  linear_feature_id bigint,
  watershed_group_code text,
  month integer,
  q_m3s double precision,
  PRIMARY KEY (linear_feature_id, month)
)"
# every group: a group with no placed outlet below it inserts nothing
WSGS=$($PSQL -tXA -c "SELECT watershed_group_code FROM whse_basemapping.fwa_watershed_groups_poly ORDER BY 1")
echo "$WSGS" | xargs -P 4 -I {} $PSQL -q -v wsg={} -f sql/pcic_crosswalk07_segments.sql
$PSQL -c "ANALYZE whse_basemapping.fwa_stream_networks_discharge_monthly"

# ----------
# 5. QA, export, clean up
# ----------
# drainage size at every placed outlet (fwapg#7), tested in qa.sql
$PSQL -f sql/qa_drainage.sql
$PSQL -c "\copy (SELECT * FROM fwapg.pcic_qa_drainage ORDER BY subid) TO 'data/qa_drainage.csv' WITH (FORMAT csv, HEADER)"

# keep the staging tables for debugging when a test fails; a NULL result (a test
# over no rows) prints "name|" and fails too
qa=$($PSQL -tXA -f sql/qa.sql)
echo "$qa"
if [ -z "$qa" ] || grep -qv '|t$' <<< "$qa"; then
  echo "QA failed, see sql/qa.sql; nothing exported, staging tables kept" >&2
  exit 1
fi
$PSQL -f sql/qa_report.sql
$PSQL -c "\copy whse_basemapping.pcic_fwa_crosswalk TO 'pcic_fwa_crosswalk.csv' DELIMITER ',' CSV HEADER"
$PSQL -c "\copy whse_basemapping.fwa_stream_networks_discharge_monthly TO 'fwa_stream_networks_discharge_monthly.csv' DELIMITER ',' CSV HEADER"
gzip -f pcic_fwa_crosswalk.csv fwa_stream_networks_discharge_monthly.csv
$PSQL -c "DROP TABLE fwapg.pcic_rivers, fwapg.pcic_lakes, fwapg.pcic_outlets, fwapg.pcic_candidates, fwapg.pcic_voters, fwapg.pcic_demoted, fwapg.pcic_outlet_monthly, fwapg.pcic_subbasins, fwapg.pcic_subbasins_monthly"
echo 'PCIC crosswalk complete, see whse_basemapping.pcic_fwa_crosswalk and whse_basemapping.fwa_stream_networks_discharge_monthly'
