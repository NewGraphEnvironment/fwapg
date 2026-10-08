#!/bin/bash
set -euo pipefail

# Validate the crosswalk against every Water Survey of Canada gauge in BC with
# discharge in the PCIC years. At each gauge, compare
#
#   - PCIC's own flow at the nearest PCIC river segment (no crosswalk involved)
#   - flow on the FWA segment at the gauge (fwa_stream_networks_discharge_monthly)
#   - the gauge's observed monthly means
#
# FWA / PCIC isolates crosswalk error; PCIC / observed is PCIC's model skill;
# FWA area / gauge area checks the gauge is on the right FWA stream.
#
# Needs the job's outputs and its data/ cache (data/rivers.geojson,
# data/monthly/*.csv). Writes data/qa_gauges.csv and prints a summary.

PSQL="psql $DATABASE_URL -v ON_ERROR_STOP=1"
API=https://api.weather.gc.ca/collections
PAGE=10000
YEARS=1951-01/2012-12

mkdir -p data/wsc

# stations
if [ ! -s data/wsc/stations.csv ]; then
  curl -sf --retry 5 "$API/hydrometric-stations/items?PROV_TERR_STATE_LOC=BC&limit=$PAGE&f=json" \
    | jq -r '.features[]
        | [.properties.STATION_NUMBER, .properties.STATION_NAME, .geometry.coordinates[0], .geometry.coordinates[1], .properties.DRAINAGE_AREA_GROSS]
        | @csv' > data/wsc/stations.csv.tmp
  mv data/wsc/stations.csv.tmp data/wsc/stations.csv
fi

# monthly means within the PCIC years, cached page by page
n=$(curl -sf --retry 5 "$API/hydrometric-monthly-mean/items?PROV_TERR_STATE_LOC=BC&datetime=$YEARS&limit=1&f=json" | jq '.numberMatched')
for ((offset = 0; offset < n; offset += PAGE)); do
  f=data/wsc/monthly_$(printf '%06d' $offset).csv
  if [ ! -s "$f" ]; then
    curl -sf --retry 5 "$API/hydrometric-monthly-mean/items?PROV_TERR_STATE_LOC=BC&datetime=$YEARS&limit=$PAGE&offset=$offset&f=json" \
      | jq -r '.features[].properties
          | select(.MONTHLY_MEAN_DISCHARGE != null)
          | [.STATION_NUMBER, (.DATE[0:4] | tonumber), (.DATE[5:7] | tonumber), .MONTHLY_MEAN_DISCHARGE]
          | @csv' > "$f.tmp"
    mv "$f.tmp" "$f"
  fi
done

# PCIC river network and outlet flows, reloaded from the job's cache
ogr2ogr -f PostgreSQL "PG:$DATABASE_URL" data/rivers.geojson \
  -nln fwapg.pcic_qa_rivers -overwrite -a_srs EPSG:3005 -nlt PROMOTE_TO_MULTI \
  -lco GEOMETRY_NAME=geom -select subid
$PSQL -c "DROP TABLE IF EXISTS fwapg.pcic_qa_outlet_monthly, fwapg.pcic_qa_stations, fwapg.pcic_qa_wsc_monthly"
$PSQL -c "CREATE TABLE fwapg.pcic_qa_outlet_monthly (subid integer, month integer, q_m3s double precision)"
cat data/monthly/*.csv | $PSQL -c "\copy fwapg.pcic_qa_outlet_monthly FROM STDIN WITH (FORMAT csv)"
$PSQL -c "CREATE TABLE fwapg.pcic_qa_stations (station text, name text, lon double precision, lat double precision, area_km2 double precision)"
$PSQL -c "\copy fwapg.pcic_qa_stations FROM data/wsc/stations.csv WITH (FORMAT csv)"
$PSQL -c "CREATE TABLE fwapg.pcic_qa_wsc_monthly (station text, year integer, month integer, q_m3s double precision)"
cat data/wsc/monthly_*.csv | $PSQL -c "\copy fwapg.pcic_qa_wsc_monthly FROM STDIN WITH (FORMAT csv)"

$PSQL -f sql/qa_gauges.sql
$PSQL -c "\copy (SELECT * FROM fwapg.pcic_qa_gauges ORDER BY station) TO 'data/qa_gauges.csv' WITH (FORMAT csv, HEADER)"
$PSQL -f sql/qa_gauges_report.sql

$PSQL -c "DROP TABLE fwapg.pcic_qa_rivers, fwapg.pcic_qa_outlet_monthly, fwapg.pcic_qa_stations, fwapg.pcic_qa_wsc_monthly"
