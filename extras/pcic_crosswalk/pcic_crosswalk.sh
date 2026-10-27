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
#   DAYS=1    also write the run's per-year sub-basin days (one parquet file per
#             year of the model's series) and their catalogue, pcic.series
#   FETCH_ONLY=1  stop once every batch's series is fetched (a cache warm-up)

PSQL="psql $DATABASE_URL -v ON_ERROR_STOP=1"
PCIC=https://beehive.pacificclimate.org
PAGE=1000      # features per bbox-server page
BATCH=500      # outlets per bulk timeseries request
DAYS_JOBS=4    # years of the per-year days built at once (DAYS=1)
MODEL=${MODEL:-PNWNAmet}
SCENARIO=${SCENARIO:-historical}
YEARS=${YEARS:-1951/2012}
WEEKLY=${WEEKLY:-0}
DAYS=${DAYS:-0}
FETCH_ONLY=${FETCH_ONLY:-0}

[[ "$YEARS" =~ ^([0-9]{4})/([0-9]{4})$ ]] && [ "${BASH_REMATCH[1]}" -le "${BASH_REMATCH[2]}" ] \
  || { echo "YEARS must be first/last, e.g. 1981/2010" >&2; exit 1; }
# hydromosaic's names are letters, digits, '-', '.', ', ' (e.g. "historical, ssp245"),
# which also keeps them safe to write into SQL below
[[ "$MODEL" =~ ^[A-Za-z0-9._-]+$ ]] && [[ "$SCENARIO" =~ ^[A-Za-z0-9._,\ -]+$ ]] \
  || { echo "MODEL or SCENARIO has characters hydromosaic does not use" >&2; exit 1; }
[[ "$WEEKLY" =~ ^[01]$ ]] || { echo "WEEKLY must be 0 or 1" >&2; exit 1; }
[[ "$DAYS" =~ ^[01]$ ]] || { echo "DAYS must be 0 or 1" >&2; exit 1; }
[[ "$FETCH_ONLY" =~ ^[01]$ ]] || { echo "FETCH_ONLY must be 0 or 1" >&2; exit 1; }
# pcic.series names the commit that built the per-year files, so build them only
# from a committed tree
if [ "$DAYS" = 1 ] && [ "$FETCH_ONLY" = 0 ]; then
  command -v uv > /dev/null || { echo "DAYS=1 needs uv (pcic_days.py)" >&2; exit 1; }
  git diff --quiet HEAD -- . ../../load \
    || { echo "DAYS=1 records the commit that built the files: commit the changes under extras/pcic_crosswalk and load first" >&2; exit 1; }
  COMMIT=$(git rev-parse HEAD)
fi
PERIOD=${YEARS/\//-}
# the run's name in cache directories and export files, e.g. pnwnamet_historical_1981-2010
RUN=$(printf '%s_%s_%s' "$MODEL" "$SCENARIO" "$PERIOD" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9.\n-' _)
# days in YEARS: a series that does not cover every one stops the run (cdo
# selyear only warns about years it does not have)
NDAYS=$($PSQL -tXA -c "SELECT make_date(${YEARS#*/}, 12, 31) - make_date(${YEARS%/*}, 1, 1) + 1")
# the model and scenario's name, case kept, in the per-year files and the caches
# that span the model's whole series, e.g. PNWNAmet_historical
MS=$(printf '%s_%s' "$MODEL" "$SCENARIO" | tr -cs 'A-Za-z0-9.\n-' _)
# batch lists, split markers and missing outlets, per model and scenario
SERIES=data/series/$MS
# each batch's daily series as hydromosaic serves it, every day of the model's run
NC=data/nc/$MS
# each batch reduced to the run's calendar-day climatology
DAILY=data/daily/$RUN

mkdir -p data/rivers data/lakes "$SERIES" "$NC" "$DAILY"

# the previous build's stamp and gauge checks (qa_gauges.sh) do not describe this
# one: review_build.sh refuses until this run passes QA and qa_gauges.sh is rerun.
# A fetch-only run builds nothing, so it leaves them.
[ "$FETCH_ONLY" = 1 ] || $PSQL -c "DROP TABLE IF EXISTS fwapg.pcic_qa_build, fwapg.pcic_qa_gauges"

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
# Each batch's NetCDF, every day of the model's series, is kept as $NC/<batch>.nc,
# so that another period, or the per-year days (DAYS=1), come from it without
# fetching again. It is downloaded to <batch>.nc.tmp and moved into place only once
# ncdump reads it, so a killed download is never kept; a kept file is used only if
# its outlets are the batch's.
#
# Each batch is reduced to the mean flow of each calendar day over YEARS
# (cdo ydaymean bins by month and day, Feb 29 on its own), so that months, weeks
# or any other period come from one fetch. Each batch leaves
# $DAILY/<batch>.csv (subid,month,day,q_m3s; empty only for a missing outlet), and
# in $SERIES a <batch>.split marker for a batch that was halved or a
# <batch>.missing marker for an outlet with no series, so a re-run resumes where it
# stopped. Remove $DAILY to reduce the run again from the kept files; remove $NC and
# $SERIES to fetch the model and scenario again.

# the outlets of a NetCDF, comma-separated, in its basin_name order
nc_outlets() {
  ncdump -v basin_name "$1" | sed -n '/basin_name =/,/;/p' | grep -oE '"[^"]+"' | tr -d '"' | paste -sd, -
}

# reduce the kept NetCDF $1 to the run's calendar-day climatology, $2
reduce_batch() {
  local nc=$1 out=$2 tmp outlets dates miss
  tmp=$DAILY/$(basename "$nc" .nc)
  # mean of each calendar day over YEARS; outlet order is the file's basin_name
  # order, day order the reduced file's dates. A series without every day of
  # YEARS, or with a missing value in them, stops the run: every day must count,
  # so that a longer period's mean can weight each calendar day by its count in
  # YEARS (fwapg.pcic_day_bins).
  # This runs under xargs without set -e, so every step is checked.
  outlets=$(nc_outlets "$nc") \
    && [ -n "$outlets" ] \
    && [ "$(cdo -s ntime -selyear,"$YEARS" "$nc" 2> /dev/null)" = "$NDAYS" ] \
    && miss=$(cdo -s -outputf,%.0f -fldsum -timsum -setmisstoc,1 -setrtoc,-1e300,1e300,0 -selyear,"$YEARS" "$nc" 2> /dev/null) \
    && [ "$miss" = 0 ] \
    && cdo -s -O ydaymean -selyear,"$YEARS" "$nc" "${tmp}_day.nc" \
    && dates=$(cdo -s showdate "${tmp}_day.nc" | tr -s ' \n' '\n\n' | grep -v '^$' | paste -sd, -) \
    && [ -n "$dates" ] \
    && ncdump -v streamflow "${tmp}_day.nc" > "${tmp}_day.cdl" \
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
    END { if (k != nd * n) exit 1 }' "${tmp}_day.cdl" > "$out.tmp" \
    || { echo "unexpected daily array in ${tmp}_day.cdl" >&2; return 255; }
  mv "$out.tmp" "$out" && rm -f "${tmp}_day.nc" "${tmp}_day.cdl"
}

fetch_batch() {
  local ids=$1 b out nc code n try
  b=$(basename "$1" .txt)
  out=$DAILY/$b.csv
  nc=$NC/$b.nc
  if [ -e "${ids%.txt}.split" ]; then
    fetch_batch "${ids%.txt}a.txt" && fetch_batch "${ids%.txt}b.txt"
    return
  fi
  if [ -e "${ids%.txt}.missing" ]; then
    [ -e "$out" ] || : > "$out"
    return
  fi
  # a kept file of this batch's outlets: reduce it if the run has not
  if [ -e "$nc" ] && [ "$(nc_outlets "$nc" | tr , '\n' | sort)" = "$(sort "$ids")" ]; then
    [ -e "$out" ] || reduce_batch "$nc" "$out"
    return
  fi
  [ -e "$out" ] && [ "$DAYS" = 0 ] && return 0
  n=$(wc -l < "$ids")
  # one line per request, since xargs' children are not traced: a run from kept
  # files prints none
  echo "fetching $b from hydromosaic" >&2
  for try in 1 2 3; do
    code=$(jq -R -s -c --arg model "$MODEL" --arg scenario "$SCENARIO" \
        '{subids: (split("\n") | map(select(length > 0))), model: $model, scenario: $scenario, variable: "streamflow", format: "netcdf"}' "$ids" \
      | curl -s -L --retry 5 -m 1800 -X POST "$PCIC/hydromosaic/bulk-downloads" \
          -H 'Content-Type: application/json' -d @- -o "$nc.tmp" -w '%{http_code}') || code=000
    [ "$code" = 422 ] && break
    [ "$code" = 200 ] && ncdump -h "$nc.tmp" > /dev/null 2>&1 && break
    code=failed
    sleep $((try * 30))
  done
  if [ "$code" = 200 ]; then
    mv "$nc.tmp" "$nc" || return 255
    [ -e "$out" ] || reduce_batch "$nc" "$out"
    return
  fi
  rm -f "$nc.tmp"
  if [ "$code" = 422 ] && [ "$n" -eq 1 ]; then
    cat "$ids" >> "$SERIES/missing.txt"
    touch "${ids%.txt}.missing"
    [ -e "$out" ] || : > "$out"
    return 0
  fi
  if [ "$code" != 422 ] && [ "$n" -le 50 ]; then
    echo "bulk download failed for $ids" >&2
    return 255
  fi
  head -n $((n / 2)) "$ids" > "${ids%.txt}a.txt"
  tail -n +$((n / 2 + 1)) "$ids" > "${ids%.txt}b.txt"
  touch "${ids%.txt}.split"
  fetch_batch "${ids%.txt}a.txt" && fetch_batch "${ids%.txt}b.txt"
}
export -f nc_outlets reduce_batch fetch_batch
export PCIC MODEL SCENARIO YEARS NDAYS SERIES NC DAILY DAYS

# the batch lists that were not halved (the ones with a series, or a missing
# outlet), from the batch lists given
batch_leaves() {
  local f
  for f; do
    if [ -e "${f%.txt}.split" ]; then
      batch_leaves "${f%.txt}a.txt" "${f%.txt}b.txt"
    else
      echo "$f"
    fi
  done
}

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
# the batch lists of this network, halved where hydromosaic needed it
LEAVES=$(batch_leaves $(ls "$SERIES"/batch_*.txt | grep -E '_[0-9]{4}\.txt$'))
# the per-year days are read from the kept files: every batch with a series has one
if [ "$DAYS" = 1 ]; then
  n=0
  for f in $LEAVES; do
    [ -e "${f%.txt}.missing" ] || [ -e "$NC/$(basename "$f" .txt).nc" ] || { echo "no NetCDF kept for $f" >&2; n=$((n + 1)); }
  done
  [ "$n" -eq 0 ] || exit 1
fi
if [ "$FETCH_ONLY" = 1 ]; then
  echo "fetched $MODEL / $SCENARIO: $(echo "$LEAVES" | wc -l) batches, $(cat "$SERIES/missing.txt" 2> /dev/null | wc -l) outlets with no series"
  exit 0
fi

# the days of YEARS by calendar day, with each day's count and week
$PSQL -v y1="${YEARS%/*}" -v y2="${YEARS#*/}" -f sql/pcic_crosswalk01_days.sql
$PSQL -c "DROP TABLE IF EXISTS fwapg.pcic_outlet_daily"
$PSQL -c "CREATE TABLE fwapg.pcic_outlet_daily (subid integer, month integer, day integer, q_m3s double precision, PRIMARY KEY (subid, month, day))"
# the climatology of this network's batches only: a batch halved since an earlier
# run can leave its parent's file beside its children's
for f in $LEAVES; do
  [ -e "$DAILY/$(basename "$f" .txt).csv" ] || { echo "no climatology for $f in $DAILY" >&2; exit 1; }
done
for f in $LEAVES; do cat "$DAILY/$(basename "$f" .txt).csv"; done \
  | $PSQL -c "\copy fwapg.pcic_outlet_daily FROM STDIN WITH (FORMAT csv)"
# every outlet with a series has every calendar day of YEARS
n=$($PSQL -tXA -c "SELECT count(*) FROM (SELECT subid FROM fwapg.pcic_outlet_daily GROUP BY subid HAVING count(*) != (SELECT count(*) FROM fwapg.pcic_day_bins WHERE n_days > 0)) s")
[ "$n" -eq 0 ] || { echo "$n outlets lack calendar days of $YEARS" >&2; exit 1; }
# outlets with no series, counted where placement reads them (no_series in
# pcic_crosswalk04_select.sql). 28 of 48,716 had none for PNWNAmet in 2026-10; many
# more is a run that hydromosaic serves for only part of the network, or a fetch
# gone wrong
n=$($PSQL -tXA -c "SELECT count(*) FROM fwapg.pcic_outlets o WHERE NOT EXISTS (SELECT 1 FROM fwapg.pcic_outlet_daily q WHERE q.subid = o.subid)")
[ "$n" -le 100 ] || { echo "$n outlets have no series in this run, see $SERIES/missing.txt" >&2; exit 1; }

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
$PSQL -v model="$MODEL" -v scenario="$SCENARIO" -v period="$PERIOD" -v weekly="$WEEKLY" -v days="$DAYS" -f sql/pcic_export.sql
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

# ----------
# 6. Per-year sub-basin days (DAYS=1)
# ----------
# Each year of the model's series, from the kept NetCDF through the climatology's
# steps (sql/pcic_crosswalk06_daily.sql), into one parquet file per year in
# $DAYDIR (days_build.sh), routed to segments by whoever reads
# it, through pcic.segment_weights (README). Every year is also kept as monthly
# means in fwapg.pcic_subbasins_months for sql/qa_report_days.sql. A year whose
# file is kept, routed on this crosswalk (its metadata says), is not rebuilt, so a
# re-run resumes; its months are read back from the file. A kept file routed on
# another crosswalk is rebuilt. DAYS_JOBS years are built at once, each in tables
# of its own.
DAYDIR=data/days/$MS
if [ "$DAYS" = 1 ]; then
  mkdir -p "$DAYDIR"
  NCS=$(for f in $LEAVES; do [ -e "${f%.txt}.missing" ] || echo "$NC/$(basename "$f" .txt).nc"; done)
  SERIES_YEARS=$(cdo -s showyear "$(echo "$NCS" | head -1)" | tr -s ' ' '\n' | grep -v '^$')
  $PSQL -c "DROP TABLE IF EXISTS fwapg.pcic_subbasins_months"
  $PSQL -c "CREATE TABLE fwapg.pcic_subbasins_months (year integer, subid integer, month integer, q_local double precision, q_acc double precision, PRIMARY KEY (year, subid, month))"
  CROSSWALK_MD5=$($PSQL -tXA -c "SELECT md5(string_agg(x::text, '|' ORDER BY x.subid)) FROM pcic.fwa_crosswalk x")
  RAN_ALL=1
  TODO=
  for y in $SERIES_YEARS; do
    f=$DAYDIR/pcic.subbasin_days.$MS.$y.parquet
    if [ -e "$f" ] && [ "$(uv run -q --script pcic_days.py meta "$f" | cut -d, -f1)" != "$CROSSWALK_MD5" ]; then
      echo "$f was routed on another crosswalk: rebuilding it"
      rm "$f"
    fi
    if [ -e "$f" ]; then
      RAN_ALL=0
      uv run -q --script pcic_days.py months "$f" | $PSQL -c "\copy fwapg.pcic_subbasins_months FROM STDIN WITH (FORMAT csv)"
    else
      TODO="$TODO $y"
    fi
  done
  # shellcheck disable=SC2086
  [ -z "$TODO" ] || printf '%s\n' $TODO \
    | xargs -P $DAYS_JOBS -I {} ./days_build.sh {} "$DAYDIR/pcic.subbasin_days.$MS.{}.parquet" "$CROSSWALK_MD5" "$COMMIT" $NCS

  # the published files' mean over YEARS against the climatology, and (when every
  # year ran here) the float64 monthly means against the run's; a failure keeps the
  # staging tables, as qa.sql's does
  $PSQL -c "DROP TABLE IF EXISTS fwapg.pcic_days_means" \
    -c "CREATE TABLE fwapg.pcic_days_means (subid integer, month integer, day integer, q_local double precision, q_acc double precision, abs_local double precision, abs_acc double precision, n integer, PRIMARY KEY (subid, month, day))"
  uv run -q --script pcic_days.py means "${YEARS%/*}" "${YEARS#*/}" "$DAYDIR"/pcic.subbasin_days."$MS".*.parquet \
    | $PSQL -c "\copy fwapg.pcic_days_means FROM STDIN WITH (FORMAT csv)"
  qa=$($PSQL -tXA -v ran_all=$RAN_ALL -v y1="${YEARS%/*}" -v y2="${YEARS#*/}" -f sql/qa_days.sql)
  echo "$qa"
  if [ -z "$qa" ] || grep -qv '|t$' <<< "$qa"; then
    echo "QA of the per-year days failed, see sql/qa_days.sql; the catalogue is not exported, staging tables kept" >&2
    exit 1
  fi
  $PSQL -f sql/qa_report_days.sql

  # the catalogue: one row per file, every year of the series
  $PSQL -c "DROP TABLE IF EXISTS fwapg.pcic_series_files" \
    -c "CREATE TABLE fwapg.pcic_series_files (year integer, rows bigint, subbasins bigint, q_local_sum bigint, q_acc_sum bigint, bytes bigint, crosswalk_md5 text, commit text)"
  uv run -q --script pcic_days.py fingerprint "$DAYDIR"/pcic.subbasin_days."$MS".*.parquet \
    | $PSQL -c "\copy fwapg.pcic_series_files FROM STDIN WITH (FORMAT csv)"
  $PSQL -v model="$MODEL" -v scenario="$SCENARIO" -v years="$(echo $SERIES_YEARS | tr ' ' ,)" -f sql/pcic_export_days.sql
fi
# every run writes the catalogue as the database holds it (empty until a DAYS=1
# run), since the upload takes every pcic.*.csv.gz and load/pcic.sql reads it
export_table pcic.series "SELECT * FROM pcic.series ORDER BY model, scenario, year"

$PSQL -c "DROP TABLE IF EXISTS fwapg.pcic_qa_outlets, fwapg.pcic_qa_candidates"
$PSQL -c "ALTER TABLE fwapg.pcic_outlets RENAME TO pcic_qa_outlets"
$PSQL -c "ALTER TABLE fwapg.pcic_candidates RENAME TO pcic_qa_candidates"
# stamp the crosswalk and run the kept pcic_qa_* tables belong to (their flows are
# the run's), once all of them are in place, so review_build.sh can tell it from
# one placed by another run or loaded by load.sh
$PSQL -c "CREATE TABLE fwapg.pcic_qa_build AS
  SELECT md5(string_agg(x::text, '|' ORDER BY x.subid)) AS crosswalk_md5, now() AS built_at,
    r.model, r.scenario, r.period, r.monthly_rows, r.monthly_q_sum
  FROM pcic.fwa_crosswalk x, pcic.runs r
  WHERE (r.model, r.scenario, r.period) = ('$MODEL', '$SCENARIO', '$PERIOD')
  GROUP BY r.model, r.scenario, r.period, r.monthly_rows, r.monthly_q_sum"
$PSQL -c "DROP TABLE fwapg.pcic_rivers, fwapg.pcic_lakes, fwapg.pcic_voters, fwapg.pcic_demoted, fwapg.pcic_fwa_crosswalk,
  fwapg.pcic_day_bins, fwapg.pcic_outlet_daily, fwapg.pcic_subbasins, fwapg.pcic_subbasins_daily, fwapg.pcic_segment_weights"
for st in $STEPS; do
  $PSQL -c "DROP TABLE fwapg.pcic_outlet_${st#*:}, fwapg.pcic_subbasins_${st#*:}, fwapg.pcic_discharge_${st#*:}"
done
$PSQL -c "DROP TABLE IF EXISTS fwapg.pcic_subbasins_months, fwapg.pcic_days_means, fwapg.pcic_series_files"
echo "PCIC crosswalk complete for $MODEL / $SCENARIO / $PERIOD, see pcic.runs"
