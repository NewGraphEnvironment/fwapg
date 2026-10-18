#!/bin/bash
set -euo pipefail

# Validate the crosswalk against every Water Survey of Canada gauge in BC with
# discharge in the run's years. At each gauge, compare
#
#   - PCIC's own flow at the nearest PCIC river segment (no crosswalk involved)
#   - flow on the FWA segment at the gauge (pcic.discharge_monthly)
#   - the gauge's observed monthly means
#
# FWA / PCIC isolates crosswalk error; PCIC / observed is PCIC's model skill;
# FWA area / gauge area checks the gauge is on the right FWA stream.
#
# The run is set as for pcic_crosswalk.sh (MODEL, SCENARIO, YEARS, with the same
# defaults). Needs the run in pcic.discharge_monthly and the job's data/ cache
# (data/rivers.geojson, and the run's daily climatology in data/daily/<run>/).
# Writes data/qa_gauges.csv and prints a summary.

PSQL="psql $DATABASE_URL -v ON_ERROR_STOP=1"
API=https://api.weather.gc.ca/collections
PAGE=10000
MODEL=${MODEL:-PNWNAmet}
SCENARIO=${SCENARIO:-historical}
YEARS=${YEARS:-1951/2012}
[[ "$YEARS" =~ ^([0-9]{4})/([0-9]{4})$ ]] || { echo "YEARS must be first/last, e.g. 1981/2010" >&2; exit 1; }
PERIOD=${YEARS/\//-}
RUN=$(printf '%s_%s_%s' "$MODEL" "$SCENARIO" "$PERIOD" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9.\n-' _)
DAILY=data/daily/$RUN
WSC=data/wsc/$PERIOD
ls "$DAILY"/*.csv > /dev/null || { echo "no daily climatology for the run in $DAILY: run pcic_crosswalk.sh for it" >&2; exit 1; }
[[ "$MODEL" =~ ^[A-Za-z0-9._-]+$ ]] && [[ "$SCENARIO" =~ ^[A-Za-z0-9._,\ -]+$ ]] \
  || { echo "MODEL or SCENARIO has characters hydromosaic does not use" >&2; exit 1; }
# the run's monthly flow must be in pcic.discharge_monthly, all of it, or every
# gauge reads no FWA flow
ok=$($PSQL -tXA -c "SELECT count(*) = max(r.monthly_rows) AND count(*) > 0
  FROM pcic.runs r
  LEFT JOIN pcic.discharge_monthly d ON (d.model, d.scenario, d.period) = (r.model, r.scenario, r.period)
  WHERE (r.model, r.scenario, r.period) = ('$MODEL', '$SCENARIO', '$PERIOD')")
[ "$ok" = t ] || { echo "pcic.discharge_monthly does not hold the run $MODEL / $SCENARIO / $PERIOD as pcic.runs lists it" >&2; exit 1; }

mkdir -p "$WSC"

# stations
if [ ! -s "$WSC/stations.csv" ]; then
  curl -sf --retry 5 "$API/hydrometric-stations/items?PROV_TERR_STATE_LOC=BC&limit=$PAGE&f=json" \
    | jq -r '.features[]
        | [.properties.STATION_NUMBER, .properties.STATION_NAME, .geometry.coordinates[0], .geometry.coordinates[1], .properties.DRAINAGE_AREA_GROSS]
        | @csv' > "$WSC/stations.csv.tmp"
  mv "$WSC/stations.csv.tmp" "$WSC/stations.csv"
fi

# monthly means within the run's years, cached page by page per period (a page is
# named by its offset only, so another period's pages would be read as this one's)
DATETIME="${YEARS%/*}-01/${YEARS#*/}-12"
n=$(curl -sf --retry 5 "$API/hydrometric-monthly-mean/items?PROV_TERR_STATE_LOC=BC&datetime=$DATETIME&limit=1&f=json" | jq '.numberMatched')
for ((offset = 0; offset < n; offset += PAGE)); do
  f=$WSC/monthly_$(printf '%06d' $offset).csv
  if [ ! -s "$f" ]; then
    curl -sf --retry 5 "$API/hydrometric-monthly-mean/items?PROV_TERR_STATE_LOC=BC&datetime=$DATETIME&limit=$PAGE&offset=$offset&f=json" \
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
# PCIC's monthly flow at every outlet, from the run's daily climatology weighted
# by each calendar day's count in YEARS (as pcic_crosswalk08_periods.sql; the
# counts are made here, not in the job's fwapg.pcic_day_bins, which a build may
# be using)
$PSQL -c "DROP TABLE IF EXISTS fwapg.pcic_qa_outlet_daily"
$PSQL -c "CREATE TABLE fwapg.pcic_qa_outlet_daily (subid integer, month integer, day integer, q_m3s double precision)"
cat "$DAILY"/*.csv | $PSQL -c "\copy fwapg.pcic_qa_outlet_daily FROM STDIN WITH (FORMAT csv)"
$PSQL -c "CREATE TABLE fwapg.pcic_qa_outlet_monthly AS
  SELECT q.subid, q.month, sum(q.q_m3s * b.n_days) / sum(b.n_days) AS q_m3s
  FROM fwapg.pcic_qa_outlet_daily q
  INNER JOIN (
    SELECT extract(month FROM d)::integer AS month, extract(day FROM d)::integer AS day, count(*) AS n_days
    FROM generate_series(make_date(${YEARS%/*}, 1, 1), make_date(${YEARS#*/}, 12, 31), interval '1 day') AS d
    GROUP BY 1, 2
  ) b ON b.month = q.month AND b.day = q.day
  GROUP BY q.subid, q.month"
$PSQL -c "CREATE TABLE fwapg.pcic_qa_stations (station text, name text, lon double precision, lat double precision, area_km2 double precision)"
$PSQL -c "\copy fwapg.pcic_qa_stations FROM '$WSC/stations.csv' WITH (FORMAT csv)"
$PSQL -c "CREATE TABLE fwapg.pcic_qa_wsc_monthly (station text, year integer, month integer, q_m3s double precision)"
cat "$WSC"/monthly_*.csv | $PSQL -c "\copy fwapg.pcic_qa_wsc_monthly FROM STDIN WITH (FORMAT csv)"

$PSQL -v model="$MODEL" -v scenario="$SCENARIO" -v period="$PERIOD" -f sql/qa_gauges.sql
$PSQL -c "\copy (SELECT * FROM fwapg.pcic_qa_gauges ORDER BY station) TO 'data/qa_gauges.csv' WITH (FORMAT csv, HEADER)"
$PSQL -f sql/qa_gauges_report.sql

$PSQL -c "DROP TABLE fwapg.pcic_qa_rivers, fwapg.pcic_qa_outlet_daily, fwapg.pcic_qa_outlet_monthly, fwapg.pcic_qa_stations, fwapg.pcic_qa_wsc_monthly"
