#!/bin/bash
set -euxo pipefail

# Crosswalk PCIC hydromosaic sub-basin outlets to FWA streams and derive
# monthly (and optionally weekly) flow per FWA stream segment for one PCIC run.
# See README.md.
#
# The run is set by the environment, defaulting to the first build:
#   MODEL     hydromosaic model, e.g. PNWNAmet or CNRM-ESM2-1
#   SCENARIO  hydromosaic scenario, e.g. historical or "historical, ssp245"
#   YEARS     years averaged, first/last (PNWNAmet runs 1950-2012; day 1 is a
#             model start-up artefact, so the default drops 1950)
#   WEEKLY=1  also build weekly flow; monthly flow is always built

PSQL="psql $DATABASE_URL -v ON_ERROR_STOP=1"
PCIC=https://beehive.pacificclimate.org
PAGE=1000      # features per bbox-server page
BATCH=500      # outlets per bulk timeseries request
MODEL=${MODEL:-PNWNAmet}
SCENARIO=${SCENARIO:-historical}
YEARS=${YEARS:-1951/2012}
WEEKLY=${WEEKLY:-0}

[[ "$YEARS" =~ ^([0-9]{4})/([0-9]{4})$ ]] && [ "${BASH_REMATCH[1]}" -le "${BASH_REMATCH[2]}" ] \
  || { echo "YEARS must be first/last, e.g. 1981/2010" >&2; exit 1; }
# hydromosaic's names are letters, digits, '-', '.', ', ' (e.g. "historical, ssp245"),
# which also keeps them safe to write into SQL below
[[ "$MODEL" =~ ^[A-Za-z0-9._-]+$ ]] && [[ "$SCENARIO" =~ ^[A-Za-z0-9._,\ -]+$ ]] \
  || { echo "MODEL or SCENARIO has characters hydromosaic does not use" >&2; exit 1; }
[[ "$WEEKLY" =~ ^[01]$ ]] || { echo "WEEKLY must be 0 or 1" >&2; exit 1; }
PERIOD=${YEARS/\//-}
# the run's name in cache directories and export files, e.g. pnwnamet_historical_1981-2010
RUN=$(printf '%s_%s_%s' "$MODEL" "$SCENARIO" "$PERIOD" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9.\n-' _)
SERIES=data/series/$RUN
DAILY=data/daily/$RUN

mkdir -p data/rivers data/lakes "$SERIES" "$DAILY"

# the previous build's stamp and gauge checks (qa_gauges.sh) do not describe this
# one: review_build.sh refuses until this run passes QA and qa_gauges.sh is rerun
$PSQL -c "DROP TABLE IF EXISTS fwapg.pcic_qa_build, fwapg.pcic_qa_gauges"

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
# 2. The run's streamflow, reduced to a daily climatology per outlet
# ----------
# The bulk endpoint returns daily NetCDF for many outlets, but only from one
# source file per request (one domain); a mixed request returns 422. Batches are
# drawn per tree, ordered by root, and halved on 422 until each part is
# single-domain. An outlet that returns 422 on its own has no series and is
# logged to $SERIES/missing.txt. A batch of more than 50 outlets that keeps
# failing otherwise (502s and truncated files under load) is halved too; below
# that, the failure stops the run (exit 255 stops xargs).
#
# Each batch is reduced to the mean flow of each calendar day over YEARS
# (cdo ydaymean bins by month and day, Feb 29 on its own), so that months, weeks
# or any other period come from one fetch. Each batch leaves
# $DAILY/<batch>.csv (subid,month,day,q_m3s; empty only for a missing outlet) or a
# <batch>.split marker in $SERIES, so a re-run resumes where it stopped. Remove
# $DAILY and $SERIES to fetch the run again.
fetch_batch() {
  local ids=$1 out=$DAILY/$(basename "$1" .txt).csv nc code n try outlets dates miss
  [ -e "$out" ] && return 0
  n=$(wc -l < "$ids")
  if [ ! -e "${ids%.txt}.split" ]; then
    nc=${ids%.txt}.nc
    for try in 1 2 3; do
      code=$(jq -R -s -c --arg model "$MODEL" --arg scenario "$SCENARIO" \
          '{subids: (split("\n") | map(select(length > 0))), model: $model, scenario: $scenario, variable: "streamflow", format: "netcdf"}' "$ids" \
        | curl -s -L --retry 5 -m 1800 -X POST "$PCIC/hydromosaic/bulk-downloads" \
            -H 'Content-Type: application/json' -d @- -o "$nc" -w '%{http_code}') || code=000
      [ "$code" = 422 ] && break
      [ "$code" = 200 ] && ncdump -h "$nc" > /dev/null 2>&1 && break
      code=failed
      sleep $((try * 30))
    done
    if [ "$code" = 200 ]; then
      # mean of each calendar day over YEARS; outlet order is the file's basin_name
      # order, day order the reduced file's dates. A series with a missing day in
      # YEARS stops the run: every day must count, so that a longer period's mean
      # can weight each calendar day by its count in YEARS (fwapg.pcic_day_bins).
      # This runs under xargs without set -e, so every step is checked.
      outlets=$(ncdump -v basin_name "$nc" | sed -n '/basin_name =/,/;/p' | grep -oE '"[^"]+"' | tr -d '"' | paste -sd, -) \
        && [ -n "$outlets" ] \
        && miss=$(cdo -s -outputf,%.0f -fldsum -timsum -setmisstoc,1 -setrtoc,-1e300,1e300,0 -selyear,"$YEARS" "$nc" 2> /dev/null) \
        && [ "$miss" = 0 ] \
        && cdo -s -O ydaymean -selyear,"$YEARS" "$nc" "${nc%.nc}_day.nc" \
        && dates=$(cdo -s showdate "${nc%.nc}_day.nc" | tr -s ' \n' '\n\n' | grep -v '^$' | paste -sd, -) \
        && [ -n "$dates" ] \
        && ncdump -v streamflow "${nc%.nc}_day.nc" > "${nc%.nc}_day.cdl" \
        || { echo "reducing $nc failed" >&2; return 255; }
      # ncdump prints the (day, outlet) array row-major; "_" is a fill value
      awk -v ids="$outlets" -v dates="$dates" '
        BEGIN {
          n = split(ids, sid, ",")
          nd = split(dates, dt, ",")
          for (t = 1; t <= nd; t++) { split(dt[t], ymd, "-"); md[t] = (ymd[2] + 0) "," (ymd[3] + 0) }
        }
        /^ streamflow =/ { on = 1; next }
        on {
          last = /;/
          gsub(/[;,]/, " ")
          for (i = 1; i <= NF; i++) {
            k++
            if ($i != "_") print sid[(k - 1) % n + 1] "," md[int((k - 1) / n) + 1] "," $i
          }
          if (last) exit
        }
        END { if (k != nd * n) exit 1 }' "${nc%.nc}_day.cdl" > "$out.tmp" \
        || { echo "unexpected daily array in ${nc%.nc}_day.cdl" >&2; return 255; }
      mv "$out.tmp" "$out"
      rm -f "$nc" "${nc%.nc}_day.nc" "${nc%.nc}_day.cdl"
      return 0
    fi
    rm -f "$nc"
    if [ "$code" = 422 ] && [ "$n" -eq 1 ]; then
      cat "$ids" >> "$SERIES/missing.txt"
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
export PCIC MODEL SCENARIO YEARS SERIES DAILY

# a wrong MODEL or SCENARIO is a 422 for every outlet, which the batching would
# read as mixed domains and halve down to every outlet missing: check that
# hydromosaic lists the run first, at an outlet that carries every series
jq -e --arg model "$MODEL" --arg scenario "$SCENARIO" \
  'any(.[]; .model == $model and .scenario == $scenario and .variable == "streamflow")' \
  <(curl -sf --retry 5 "$PCIC/hydromosaic/outlets/4008184/timeseries") > /dev/null \
  || { echo "hydromosaic lists no streamflow for model '$MODEL', scenario '$SCENARIO'" >&2; exit 1; }

rm -f "$SERIES"/batch_???_????.txt
$PSQL -tXA -F ' ' -c "SELECT root_subid / 1000000, subid FROM fwapg.pcic_outlets ORDER BY root_subid / 1000000, root_subid, subid" \
  | awk -v b=$BATCH -v dir="$SERIES" '{ if ($1 != g || ++n > b) { g = $1; n = 1; k++ } print $2 > sprintf("%s/batch_%03d_%04d.txt", dir, $1, k) }'
ls "$SERIES"/batch_*.txt | grep -E '_[0-9]{4}\.txt$' | xargs -P 3 -I {} bash -c 'fetch_batch "$1"' _ {}

# 28 of 48,716 outlets had no PNWNAmet series in 2026-10; many more is a run that
# hydromosaic serves for only part of the network, or a fetch gone wrong
n=$(cat "$SERIES/missing.txt" 2> /dev/null | wc -l)
[ "$n" -le 100 ] || { echo "$n outlets have no series in this run, see $SERIES/missing.txt" >&2; exit 1; }

# the days of YEARS by calendar day, with each day's count and week
$PSQL -v y1="${YEARS%/*}" -v y2="${YEARS#*/}" -f sql/pcic_crosswalk01_days.sql
$PSQL -c "DROP TABLE IF EXISTS fwapg.pcic_outlet_daily"
$PSQL -c "CREATE TABLE fwapg.pcic_outlet_daily (subid integer, month integer, day integer, q_m3s double precision, PRIMARY KEY (subid, month, day))"
cat "$DAILY"/*.csv | $PSQL -c "\copy fwapg.pcic_outlet_daily FROM STDIN WITH (FORMAT csv)"
# every outlet with a series has every calendar day of YEARS
n=$($PSQL -tXA -c "SELECT count(*) FROM (SELECT subid FROM fwapg.pcic_outlet_daily GROUP BY subid HAVING count(*) != (SELECT count(*) FROM fwapg.pcic_day_bins)) s")
[ "$n" -eq 0 ] || { echo "$n outlets lack calendar days of $YEARS" >&2; exit 1; }

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
# 4. Flow per FWA stream segment
# ----------
# sub-basins and their flow per calendar day
$PSQL -f sql/pcic_crosswalk06_subbasins.sql
# each segment's sub-basin, share and outlets above (no flow), per group: a group
# with no placed outlet below it inserts nothing
$PSQL -c "DROP TABLE IF EXISTS fwapg.pcic_segment_weights"
$PSQL -c "CREATE TABLE fwapg.pcic_segment_weights (
  linear_feature_id bigint PRIMARY KEY,
  watershed_group_code text,
  subid integer,
  share double precision,
  upstream_subids integer[]
)"
WSGS=$($PSQL -tXA -c "SELECT watershed_group_code FROM whse_basemapping.fwa_watershed_groups_poly ORDER BY 1")
echo "$WSGS" | xargs -P 4 -I {} $PSQL -q -v wsg={} -f sql/pcic_crosswalk07_segments.sql
$PSQL -c "ANALYZE fwapg.pcic_segment_weights"
# per period: mean outlet and sub-basin flow, then segment flow from the weights.
# Monthly is always built, and is what qa.sql tests.
STEPS="month:monthly"
[ "$WEEKLY" = 1 ] && STEPS="$STEPS week:weekly"
for st in $STEPS; do
  step=${st%:*}
  table=${st#*:}
  $PSQL -v step=$step -v table=$table -f sql/pcic_crosswalk08_periods.sql
  $PSQL -c "DROP TABLE IF EXISTS fwapg.pcic_discharge_$table"
  $PSQL -c "CREATE TABLE fwapg.pcic_discharge_$table (
    linear_feature_id bigint,
    watershed_group_code text,
    $step integer,
    q_raw double precision,
    q_m3s double precision,
    PRIMARY KEY (linear_feature_id, $step)
  )"
  echo "$WSGS" | xargs -P 4 -I {} $PSQL -q -v wsg={} -v step=$step -v table=$table -f sql/pcic_crosswalk09_discharge.sql
  $PSQL -c "ANALYZE fwapg.pcic_discharge_$table"
done

# ----------
# 5. QA, export, clean up
# ----------
# drainage size at every placed outlet (fwapg#7), tested in qa.sql
$PSQL -f sql/qa_drainage.sql
$PSQL -c "\copy (SELECT * FROM fwapg.pcic_qa_drainage ORDER BY subid) TO 'data/qa_drainage.csv' WITH (FORMAT csv, HEADER)"
# does each placed outlet's PCIC segment follow the FWA line it is on (fwapg#8), tested in qa.sql
$PSQL -f sql/qa_following.sql
$PSQL -c "\copy (SELECT * FROM fwapg.pcic_qa_following ORDER BY subid) TO 'data/qa_following.csv' WITH (FORMAT csv, HEADER)"
# mean annual flow at each placed outlet, PCIC's and accumulated on the FWA, kept
# with the outlets and candidates for the review in fwapg#8 (review_build.sh)
$PSQL -c "DROP TABLE IF EXISTS fwapg.pcic_qa_flow"
$PSQL -c "CREATE TABLE fwapg.pcic_qa_flow AS
  SELECT m.subid, avg(q.q_m3s) AS q_pcic, avg(m.q_acc) AS q_fwa
  FROM fwapg.pcic_subbasins_monthly m
  INNER JOIN fwapg.pcic_outlet_monthly q ON q.subid = m.subid AND q.month = m.month
  GROUP BY m.subid"

# keep the staging tables for debugging when a test fails; a NULL result (a test
# over no rows) prints "name|" and fails too
qa=$($PSQL -tXA -f sql/qa.sql)
[ "$WEEKLY" = 1 ] && qa="$qa"$'\n'"$($PSQL -tXA -f sql/qa_weekly.sql)"
echo "$qa"
if [ -z "$qa" ] || grep -qv '|t$' <<< "$qa"; then
  echo "QA failed, see sql/qa.sql and sql/qa_weekly.sql; nothing exported, staging tables kept" >&2
  exit 1
fi
$PSQL -f sql/qa_report.sql
[ "$WEEKLY" = 1 ] && $PSQL -v step=week -v table=weekly -f sql/qa_report_clamped.sql
$PSQL -v step=month -v table=monthly -f sql/qa_report_clamped.sql

# into the pcic schema: the crosswalk and weights shared by every run, and this
# run's rows, swapped in one transaction (sql/pcic_export.sql)
$PSQL -f ../../load/pcic_schema.sql
$PSQL -v model="$MODEL" -v scenario="$SCENARIO" -v period="$PERIOD" -v weekly="$WEEKLY" -f sql/pcic_export.sql
# one file per table, and per table and run for the run's rows. pcic.runs lists
# every run in this database, with the fingerprints load/pcic_*.sql check.
export_table() {
  $PSQL -c "\copy ($2) TO STDOUT WITH (FORMAT csv, HEADER)" | gzip > "$1.csv.gz.tmp"
  mv "$1.csv.gz.tmp" "$1.csv.gz"
}
RUNSQL="model = '$MODEL' AND scenario = '$SCENARIO' AND period = '$PERIOD'"
export_table pcic.runs "SELECT * FROM pcic.runs ORDER BY model, scenario, period"
export_table pcic.day_bins "SELECT * FROM pcic.day_bins ORDER BY month, day"
export_table pcic.fwa_crosswalk "SELECT * FROM pcic.fwa_crosswalk ORDER BY subid"
export_table pcic.segment_weights "SELECT * FROM pcic.segment_weights ORDER BY linear_feature_id"
export_table "pcic.subbasin_daily.$RUN" "SELECT * FROM pcic.subbasin_daily WHERE $RUNSQL ORDER BY subid, month, day"
export_table "pcic.discharge_monthly.$RUN" "SELECT * FROM pcic.discharge_monthly WHERE $RUNSQL ORDER BY linear_feature_id, month"
[ "$WEEKLY" = 1 ] && export_table "pcic.discharge_weekly.$RUN" "SELECT * FROM pcic.discharge_weekly WHERE $RUNSQL ORDER BY linear_feature_id, week"

$PSQL -c "DROP TABLE IF EXISTS fwapg.pcic_qa_outlets, fwapg.pcic_qa_candidates"
$PSQL -c "ALTER TABLE fwapg.pcic_outlets RENAME TO pcic_qa_outlets"
$PSQL -c "ALTER TABLE fwapg.pcic_candidates RENAME TO pcic_qa_candidates"
# stamp the crosswalk and run the kept pcic_qa_* tables belong to (their flows are
# the run's), once all of them are in place, so review_build.sh can tell it from
# one placed by another run or loaded by load.sh
$PSQL -c "CREATE TABLE fwapg.pcic_qa_build AS
  SELECT md5(string_agg(x::text, '|' ORDER BY x.subid)) AS crosswalk_md5, now() AS built_at,
    '$MODEL'::text AS model, '$SCENARIO'::text AS scenario, '$PERIOD'::text AS period
  FROM pcic.fwa_crosswalk x"
$PSQL -c "DROP TABLE fwapg.pcic_rivers, fwapg.pcic_lakes, fwapg.pcic_voters, fwapg.pcic_demoted, fwapg.pcic_fwa_crosswalk,
  fwapg.pcic_day_bins, fwapg.pcic_outlet_daily, fwapg.pcic_subbasins, fwapg.pcic_subbasins_daily, fwapg.pcic_segment_weights"
for st in $STEPS; do
  $PSQL -c "DROP TABLE fwapg.pcic_outlet_${st#*:}, fwapg.pcic_subbasins_${st#*:}, fwapg.pcic_discharge_${st#*:}"
done
echo "PCIC crosswalk complete for $MODEL / $SCENARIO / $PERIOD, see pcic.runs"
