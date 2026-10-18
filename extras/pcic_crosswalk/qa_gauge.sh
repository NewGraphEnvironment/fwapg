#!/bin/bash
set -euo pipefail

# Compare monthly flow on the FWA segment at a Water Survey of Canada gauge with
# the gauge's observed monthly means over the same years as the PCIC run.
#
#   ./qa_gauge.sh 08EE003                    # Bulkley River near Houston
#   YEARS=1981/2010 ./qa_gauge.sh 08EE003    # another run, set as for pcic_crosswalk.sh
#
# Needs the run in pcic.discharge_monthly.

STATION=$1
MODEL=${MODEL:-PNWNAmet}
SCENARIO=${SCENARIO:-historical}
YEARS=${YEARS:-1951/2012}
[[ "$YEARS" =~ ^([0-9]{4})/([0-9]{4})$ ]] || { echo "YEARS must be first/last, e.g. 1981/2010" >&2; exit 1; }
[[ "$MODEL" =~ ^[A-Za-z0-9._-]+$ ]] && [[ "$SCENARIO" =~ ^[A-Za-z0-9._,\ -]+$ ]] \
  || { echo "MODEL or SCENARIO has characters hydromosaic does not use" >&2; exit 1; }
YEAR_MIN=${YEARS%/*}
YEAR_MAX=${YEARS#*/}
PERIOD=$YEAR_MIN-$YEAR_MAX
PSQL="psql $DATABASE_URL -v ON_ERROR_STOP=1"
API=https://api.weather.gc.ca/collections

read -r LON LAT AREA < <(curl -sf "$API/hydrometric-stations/items?STATION_NUMBER=$STATION&f=json" \
  | jq -r '.features[0] | "\(.geometry.coordinates[0]) \(.geometry.coordinates[1]) \(.properties.DRAINAGE_AREA_GROSS)"')

if [ -z "$LON" ] || [ "$LON" = null ] || [ "$AREA" = null ]; then
  echo "station $STATION not found, or has no location or drainage area" >&2
  exit 1
fi

# observed monthly climatology: mean of the monthly means within the PCIC years
OBS=$(curl -sf "$API/hydrometric-monthly-mean/items?STATION_NUMBER=$STATION&limit=10000&f=json" \
  | jq -r --argjson y0 $YEAR_MIN --argjson y1 $YEAR_MAX '
      [.features[].properties
       | select(.MONTHLY_MEAN_DISCHARGE != null)
       | {y: (.DATE[0:4] | tonumber), m: (.DATE[5:7] | tonumber), q: .MONTHLY_MEAN_DISCHARGE}
       | select(.y >= $y0 and .y <= $y1)]
      | group_by(.m)
      | map("(\(.[0].m), \(map(.q) | add / length), \(length))")
      | join(",")')
[ -n "$OBS" ] || { echo "no observations for $STATION in $YEAR_MIN-$YEAR_MAX"; exit 1; }

$PSQL -X <<SQL
WITH obs (month, q_obs, n_years) AS (VALUES $OBS),
-- gauges sit at bridges and confluences, so of the streams within 500 m take the
-- one whose FWA upstream area is closest to the gauge's drainage area
gauge AS (
  SELECT
    c.linear_feature_id,
    c.gnis_name,
    round(c.distance_to_stream::numeric, 1) AS snap_m,
    round((ua.upstream_area_ha / 100)::numeric) AS fwa_area_km2
  FROM whse_basemapping.FWA_IndexPoint(ST_Transform(ST_SetSRID(ST_MakePoint($LON, $LAT), 4326), 3005), 500, 5) c
  INNER JOIN whse_basemapping.fwa_streams_watersheds_lut l ON c.linear_feature_id = l.linear_feature_id
  INNER JOIN whse_basemapping.fwa_watersheds_upstream_area ua ON l.watershed_feature_id = ua.watershed_feature_id
  ORDER BY abs(ln(greatest(ua.upstream_area_ha, 1) / 100 / $AREA)), c.distance_to_stream
  LIMIT 1
)
SELECT
  '$STATION' AS station,
  g.gnis_name,
  g.snap_m,
  $AREA AS gauge_area_km2,
  g.fwa_area_km2,
  o.month,
  o.n_years,
  round(o.q_obs::numeric, 2) AS q_obs,
  round(d.q_m3s::numeric, 2) AS q_pcic_fwa,
  round((d.q_m3s / nullif(o.q_obs, 0))::numeric, 2) AS ratio
FROM gauge g
CROSS JOIN obs o
LEFT JOIN pcic.discharge_monthly d
  ON d.linear_feature_id = g.linear_feature_id AND d.month = o.month
  AND (d.model, d.scenario, d.period) = ('$MODEL', '$SCENARIO', '$PERIOD')
ORDER BY o.month;
SQL
