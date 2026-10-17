#!/bin/bash
set -euo pipefail

# Build the GeoPackage for the visual review of placed outlets
# (NewGraphEnvironment/fwapg#8). Needs the job's kept QA tables (run
# pcic_crosswalk.sh, then qa_gauges.sh) and its data/ cache. Writes:
#
#   data/review/review.gpkg         the review layer and its context, blinded
#   data/review/flags.csv           why each outlet was drawn, for after the review
#   data/review/sample_design.csv   review_id to subid and strata, copied to
#                                   review/sample_design.csv (committed)
#
# The review layer carries review_id and the empty form (verdict, confidence,
# note) only; nothing in review.gpkg says why an outlet was drawn. Score the
# filled-in GeoPackage with review_score.sh.

PSQL="psql $DATABASE_URL -v ON_ERROR_STOP=1"
PG="PG:$DATABASE_URL"
SEED=fwapg8      # fixed: the same build and seed draw the same sample
CAP_RANDOM=60    # random placed outlets: the network's error rate
CAP=12           # each flagged stratum: finds a class affecting 20% of it 9 times in 10
BUFFER=2000      # context around each outlet (m)
OUT=data/review
GPKG=$OUT/review.gpkg
DESIGN=review/sample_design.csv

mkdir -p "$OUT" review

# the tables read must come from one build. pcic_crosswalk.sh drops its stamp
# (fwapg.pcic_qa_build) and pcic_qa_gauges when it starts and stamps the crosswalk's
# md5 once QA passes, so a missing stamp is a run that did not finish, a missing
# pcic_qa_gauges is qa_gauges.sh not yet run on this build, and a crosswalk that no
# longer hashes to the stamp was replaced (load.sh, or a run of other placement
# logic) and no longer matches the kept pcic_qa_* tables. load.sh replaces the
# discharge table too; a crosswalk identical to the stamp's comes from the same
# deterministic build, and so does its discharge
present=$($PSQL -tXA -c "SELECT to_regclass('fwapg.pcic_qa_build') IS NOT NULL AND to_regclass('fwapg.pcic_qa_gauges') IS NOT NULL")
[ "$present" = t ] || { echo "no fwapg.pcic_qa_build or fwapg.pcic_qa_gauges: run pcic_crosswalk.sh to the end, then qa_gauges.sh" >&2; exit 1; }
# the gauges must be from the run the kept flows are from (qa_gauges.sh takes the run as the job does)
samerun=$($PSQL -tXA -c "SELECT EXISTS (SELECT 1 FROM fwapg.pcic_qa_gauges g, fwapg.pcic_qa_build b
  WHERE (g.model, g.scenario, g.period) = (b.model, b.scenario, b.period))
  AND NOT EXISTS (SELECT 1 FROM fwapg.pcic_qa_gauges g, fwapg.pcic_qa_build b
  WHERE (g.model, g.scenario, g.period) IS DISTINCT FROM (b.model, b.scenario, b.period))")
[ "$samerun" = t ] || { echo "fwapg.pcic_qa_gauges is from another run than the job's last: rerun qa_gauges.sh with the job's MODEL, SCENARIO and YEARS" >&2; exit 1; }
same=$($PSQL -tXA -c "SELECT (SELECT crosswalk_md5 FROM fwapg.pcic_qa_build)
  = (SELECT md5(string_agg(x::text, '|' ORDER BY x.subid)) FROM pcic.fwa_crosswalk x)")
[ "$same" = t ] || { echo "the crosswalk is not the one the kept pcic_qa_* tables were built with: rerun pcic_crosswalk.sh and qa_gauges.sh" >&2; exit 1; }

# the GeoPackage is filled in place, so a rebuild (the same draw rebuilds it) must
# not delete answers. Refused while anything may hold it open or hold edits beside
# it (an open handle, a -wal, -shm or -journal, a header in WAL mode: QGIS's saves
# would go to the deleted file, or a leftover -wal replay into the new one), and
# while its review layer has any filled row. One that cannot be read counts as
# filled. A sidecar refuses even with no GeoPackage: one left by a file moved aside
# would replay into the new one. Checked before the build and again just before
# the new file is moved into place
guard_live() {
  local side mode filled
  for side in "$GPKG-wal" "$GPKG-shm" "$GPKG-journal"; do
    [ ! -e "$side" ] || { echo "$side exists: close $GPKG in QGIS, or move it aside with the GeoPackage" >&2; exit 1; }
  done
  [ -e "$GPKG" ] || return 0
  if command -v lsof > /dev/null && lsof -- "$GPKG" > /dev/null 2>&1; then
    echo "$GPKG is open in another program: close it first" >&2
    exit 1
  fi
  mode=$(od -An -j 18 -N 2 -t x1 "$GPKG" | tr -d ' \n')
  [ "$mode" = 0101 ] || { echo "$GPKG is in write-ahead-log mode ($mode): close it in QGIS first" >&2; exit 1; }
  filled=$(ogrinfo -sql "SELECT count(*) AS n FROM review
      WHERE coalesce(verdict, '') != '' OR coalesce(confidence, '') != '' OR coalesce(note, '') != ''" "$GPKG" \
    | awk '/^ *n \(/{print $NF}') || filled=
  if [ "$filled" != 0 ]; then
    echo "$GPKG holds ${filled:-unreadable} filled-in review rows; move it aside to rebuild" >&2
    exit 1
  fi
}
guard_live

$PSQL -v seed="$SEED" -v cap="$CAP" -v cap_random="$CAP_RANDOM" -f sql/review_sample.sql

# every output is written beside its live name and moved into place once the
# checks pass, so a failed build leaves the last good set, not a mix
NEW=$OUT/review.building.gpkg
NEW_DESIGN=$OUT/sample_design.building.csv
NEW_FLAGS=$OUT/flags.building.csv
rm -f "$NEW" "$NEW-wal" "$NEW-shm" "$NEW-journal" "$NEW_DESIGN" "$NEW_FLAGS"

$PSQL -c "\copy (SELECT review_id, subid, stratum, drawn FROM fwapg.pcic_review_design ORDER BY review_id, stratum) TO '$NEW_DESIGN' WITH (FORMAT csv, HEADER)"
# the committed design is the key to a review in progress: a new draw (a changed
# build or seed) must not replace it silently
if [ -e "$DESIGN" ] && ! cmp -s "$NEW_DESIGN" "$DESIGN"; then
  echo "$DESIGN exists and differs from this draw; for a new review, move it and $OUT/ aside (flags.csv is the old review's)" >&2
  exit 1
fi
sample_id=$(md5sum < "$NEW_DESIGN" | cut -c1-32)

# PCIC's network around the sample, without its ids: a subid would lead back to
# the flag lists
ogr2ogr -f PostgreSQL "$PG" data/rivers.geojson -nln fwapg.pcic_review_rivers -overwrite \
  -a_srs EPSG:3005 -nlt PROMOTE_TO_MULTI -lco GEOMETRY_NAME=geom -select subid
ogr2ogr -f PostgreSQL "$PG" data/lakes.geojson -nln fwapg.pcic_review_lakes -overwrite \
  -a_srs EPSG:3005 -nlt PROMOTE_TO_MULTI -lco GEOMETRY_NAME=geom -select subid

SAMPLE="(SELECT DISTINCT d.review_id, d.subid, o.geom, o.probe_geom
  FROM fwapg.pcic_review_design d INNER JOIN fwapg.pcic_qa_outlets o ON o.subid = d.subid)"
AREA="(SELECT ST_Union(ST_Buffer(geom, $BUFFER)) AS geom FROM $SAMPLE s)"

layer() {  # layer <name> <sql>; the first creates the GeoPackage
  local update=
  [ -e "$NEW" ] && update=-update
  # unquoted on purpose: empty for the first layer (an empty array is unbound under set -u on bash 3.2)
  ogr2ogr -f GPKG "$NEW" "$PG" $update -nln "$1" -sql "$2" -a_srs EPSG:3005
}
layer review "SELECT review_id, NULL::text AS verdict, NULL::text AS confidence, NULL::text AS note, geom
  FROM $SAMPLE s ORDER BY review_id"
layer pcic_probe "SELECT review_id, probe_geom AS geom FROM $SAMPLE s ORDER BY review_id"
layer pcic_segment "SELECT s.review_id, r.geom FROM $SAMPLE s INNER JOIN fwapg.pcic_review_rivers r ON r.subid = s.subid ORDER BY s.review_id"
layer pcic_rivers "SELECT r.geom FROM fwapg.pcic_review_rivers r, $AREA a WHERE ST_Intersects(r.geom, a.geom)"
layer pcic_lakes "SELECT l.geom FROM fwapg.pcic_review_lakes l, $AREA a WHERE ST_Intersects(l.geom, a.geom)"
# candidates unranked and without distance: the rank would give away a stratum
layer fwa_candidates "SELECT DISTINCT s.review_id, c.blue_line_key, f.gnis_name,
    ST_Force2D(whse_basemapping.FWA_LocateAlong(c.blue_line_key, c.downstream_route_measure)) AS geom
  FROM $SAMPLE s
  INNER JOIN fwapg.pcic_qa_candidates c ON c.subid = s.subid
  INNER JOIN whse_basemapping.fwa_stream_networks_sp f ON f.linear_feature_id = c.linear_feature_id
  ORDER BY s.review_id"
layer fwa_placed "SELECT s.review_id,
    ST_Force2D(whse_basemapping.FWA_LocateAlong(x.blue_line_key, x.downstream_route_measure)) AS geom
  FROM $SAMPLE s INNER JOIN pcic.fwa_crosswalk x ON x.subid = s.subid
  WHERE x.flag IS NULL ORDER BY s.review_id"
layer fwa_streams "SELECT f.blue_line_key, f.gnis_name, f.stream_order, f.edge_type, ST_Force2D(f.geom) AS geom
  FROM whse_basemapping.fwa_stream_networks_sp f, $AREA a WHERE ST_Intersects(f.geom, a.geom)"
layer sample "SELECT '$sample_id'::text AS sample_id"

# why each outlet was drawn, kept out of the review GeoPackage; review_id is
# reassigned by every draw, so each row names its sample
$PSQL -c "\copy (
  SELECT '$sample_id' AS sample_id, d.review_id,
    string_agg(d.stratum, ' ' ORDER BY d.stratum) FILTER (WHERE d.drawn) AS drawn_for,
    string_agg(d.stratum, ' ' ORDER BY d.stratum) AS strata,
    x.flag AS crosswalk_flag, x.candidate_rank, dr.flag AS drainage_flag, fo.flag AS following_flag,
    round((fl.q_fwa / nullif(fl.q_pcic, 0))::numeric, 2) AS fwa_over_pcic_flow,
    (SELECT string_agg(g.station, ' ' ORDER BY g.station) FROM fwapg.pcic_qa_gauges g
     WHERE g.pcic_subid = d.subid AND g.fwa_over_pcic NOT BETWEEN 0.9 AND 1.1 AND NOT g.any_pcic_matches_fwa) AS gauges
  FROM fwapg.pcic_review_design d
  INNER JOIN pcic.fwa_crosswalk x ON x.subid = d.subid
  LEFT JOIN fwapg.pcic_qa_drainage dr ON dr.subid = d.subid
  LEFT JOIN fwapg.pcic_qa_following fo ON fo.subid = d.subid
  LEFT JOIN fwapg.pcic_qa_flow fl ON fl.subid = d.subid
  GROUP BY d.review_id, d.subid, x.flag, x.candidate_rank, dr.flag, fo.flag, fl.q_fwa, fl.q_pcic
  ORDER BY d.review_id
) TO '$NEW_FLAGS' WITH (FORMAT csv, HEADER)"

$PSQL -c "DROP TABLE fwapg.pcic_review_rivers, fwapg.pcic_review_lakes"

# checks (ogrinfo without -q: with it, GDAL 3.13 prints no fields): the review layer holds the form and nothing else, every drawn outlet is
# in it once, each stratum drew min(cap, population), and no layer carries an id
# or a flag that would unblind the review
fields=$(ogrinfo -so "$NEW" review | awk -F: '/^[a-z_]+: /{print $1}' | paste -sd, -)
[ "$fields" = "review_id,verdict,confidence,note" ] || { echo "review layer fields: $fields" >&2; exit 1; }
n=$(ogrinfo -sql 'SELECT count(DISTINCT review_id) AS n, count(*) AS m FROM review' "$NEW" | awk '/^ *n \(/{n=$NF} /^ *m \(/{m=$NF} END {print n "," m}')
want=$($PSQL -tXA -c "SELECT count(DISTINCT review_id) FROM fwapg.pcic_review_design")
[ "$n" = "$want,$want" ] || { echo "review layer holds $n (distinct, all) review_ids, the design $want" >&2; exit 1; }
short=$($PSQL -tXA -c "
  SELECT string_agg(p.stratum, ' ')
  FROM (SELECT stratum, count(*) AS population FROM fwapg.pcic_review_strata GROUP BY stratum) p
  WHERE (SELECT count(*) FROM fwapg.pcic_review_design d WHERE d.stratum = p.stratum AND d.drawn)
    != least(CASE WHEN p.stratum = 'random' THEN $CAP_RANDOM ELSE $CAP END, p.population)")
[ -z "$short" ] || { echo "strata drawn short of min(cap, population): $short" >&2; exit 1; }
leak=$(ogrinfo -so -al "$NEW" | awk -F: '/^(subid|dowsubid|stratum|flag|candidate_rank|distance_to_stream|strata|drawn): /' | sort -u)
[ -z "$leak" ] || { echo "the review GeoPackage carries $leak" >&2; exit 1; }

$PSQL -c "DROP TABLE fwapg.pcic_review_strata"
guard_live
mv "$NEW" "$GPKG"
mv "$NEW_FLAGS" "$OUT/flags.csv"
cp "$NEW_DESIGN" "$DESIGN"
mv "$NEW_DESIGN" "$OUT/sample_design.csv"
echo "review: $want outlets in $GPKG (sample_id $sample_id); design in $DESIGN, flags in $OUT/flags.csv"
