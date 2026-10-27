#!/bin/bash
set -euo pipefail

# One year of the per-year sub-basin days (pcic_crosswalk.sh, DAYS=1; README.md):
# the year's outlet flows from the kept NetCDF into fwapg.pcic_outlet_year_<year>
# (by pcic_days.py rows), its sub-basin flows into fwapg.pcic_subbasins_year_<year>
# (by sql/pcic_crosswalk06_daily.sql, the climatology's steps), their monthly
# means added to fwapg.pcic_subbasins_months, and the year's parquet file (by
# pcic_days.py parquet, which records in it the crosswalk md5 and commit given).
# The two tables are the year's own, so that years can be
# built at once, and are dropped on exit. Prints how long each step took.
#
#   days_build.sh <year> <parquet file> <crosswalk md5> <commit> <NetCDF file...>
#
# Needs DATABASE_URL, the staging tables pcic_crosswalk06_subbasins.sql leaves
# (fwapg.pcic_outlets, pcic_fwa_crosswalk, pcic_subbasins) and
# fwapg.pcic_subbasins_months.

[ $# -ge 5 ] || { echo "usage: days_build.sh <year> <parquet file> <crosswalk md5> <commit> <NetCDF file...>" >&2; exit 1; }
y=$1
out=$2
md5=$3
commit=$4
shift 4
[[ "$y" =~ ^[0-9]{4}$ ]] || { echo "days_build.sh: not a year: $y" >&2; exit 1; }
D=$(dirname "$0")
PSQL="psql $DATABASE_URL -X -q -v ON_ERROR_STOP=1"
src=pcic_outlet_year_$y
dst=pcic_subbasins_year_$y
# exits 1 unless the year was built: under bash 3.2 an EXIT trap turns a failed
# expansion into exit 0
ok=0
trap 'rc=$?; $PSQL -c "DROP TABLE IF EXISTS fwapg.$src, fwapg.$dst" > /dev/null 2>&1; [ "$ok" = 1 ] || exit $(( rc ? rc : 1 ))' EXIT

t0=$SECONDS
$PSQL -c "DROP TABLE IF EXISTS fwapg.$src" \
  -c "CREATE TABLE fwapg.$src (subid integer, month integer, day integer, q_m3s double precision)"
uv run -q --script "$D/pcic_days.py" rows "$y" "$@" | $PSQL -c "\copy fwapg.$src FROM STDIN WITH (FORMAT csv)"
$PSQL -c "ALTER TABLE fwapg.$src ADD PRIMARY KEY (subid, month, day)" -c "ANALYZE fwapg.$src"
t1=$SECONDS
$PSQL -v src="$src" -v dst="$dst" -f "$D/sql/pcic_crosswalk06_daily.sql"
t2=$SECONDS
$PSQL -c "INSERT INTO fwapg.pcic_subbasins_months
  SELECT $y, subid, month, avg(q_local), avg(q_acc) FROM fwapg.$dst GROUP BY subid, month"
t3=$SECONDS
$PSQL -c "\copy (SELECT subid, month, day, q_local, q_acc FROM fwapg.$dst) TO STDOUT WITH (FORMAT csv)" \
  | uv run -q --script "$D/pcic_days.py" parquet "$y" "$out" "$md5" "$commit"
ok=1
echo "days $y: rows and copy $((t1 - t0)) s, 06_daily $((t2 - t1)) s, months $((t3 - t2)) s, parquet $((SECONDS - t3)) s"
