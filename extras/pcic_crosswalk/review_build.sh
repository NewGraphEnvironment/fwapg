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

$PSQL -v seed="$SEED" -v cap="$CAP" -v cap_random="$CAP_RANDOM" -f sql/review_sample.sql

$PSQL -c "\copy (SELECT review_id, subid, stratum, drawn FROM fwapg.pcic_review_design ORDER BY review_id, stratum) TO '$OUT/sample_design.csv' WITH (FORMAT csv, HEADER)"
# the committed design is the key to a review in progress: a new draw (a changed
# build or seed) must not replace it silently
if [ -e "$DESIGN" ] && ! cmp -s "$OUT/sample_design.csv" "$DESIGN"; then
  echo "$DESIGN exists and differs from this draw; move it aside if a new review is intended" >&2
  exit 1
fi
cp "$OUT/sample_design.csv" "$DESIGN"
sample_id=$(md5sum < "$DESIGN" | cut -c1-32)

# PCIC's network around the sample, without its ids: a subid would lead back to
# the flag lists
ogr2ogr -f PostgreSQL "$PG" data/rivers.geojson -nln fwapg.pcic_review_rivers -overwrite \
  -a_srs EPSG:3005 -nlt PROMOTE_TO_MULTI -lco GEOMETRY_NAME=geom -select subid
ogr2ogr -f PostgreSQL "$PG" data/lakes.geojson -nln fwapg.pcic_review_lakes -overwrite \
  -a_srs EPSG:3005 -nlt PROMOTE_TO_MULTI -lco GEOMETRY_NAME=geom -select subid

SAMPLE="(SELECT DISTINCT d.review_id, d.subid, o.geom, o.probe_geom
  FROM fwapg.pcic_review_design d INNER JOIN fwapg.pcic_qa_outlets o ON o.subid = d.subid)"
AREA="(SELECT ST_Union(ST_Buffer(geom, $BUFFER)) AS geom FROM $SAMPLE s)"

rm -f "$GPKG"
layer() {  # layer <name> <sql>; the first creates the GeoPackage
  local update=
  [ -e "$GPKG" ] && update=-update
  # unquoted on purpose: empty for the first layer (an empty array is unbound under set -u on bash 3.2)
  ogr2ogr -f GPKG "$GPKG" "$PG" $update -nln "$1" -sql "$2" -a_srs EPSG:3005
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
  FROM $SAMPLE s INNER JOIN whse_basemapping.pcic_fwa_crosswalk x ON x.subid = s.subid
  WHERE x.flag IS NULL ORDER BY s.review_id"
layer fwa_streams "SELECT f.blue_line_key, f.gnis_name, f.stream_order, f.edge_type, ST_Force2D(f.geom) AS geom
  FROM whse_basemapping.fwa_stream_networks_sp f, $AREA a WHERE ST_Intersects(f.geom, a.geom)"
layer sample "SELECT '$sample_id'::text AS sample_id"

# why each outlet was drawn, kept out of the review GeoPackage
$PSQL -c "\copy (
  SELECT d.review_id,
    string_agg(d.stratum, ' ' ORDER BY d.stratum) FILTER (WHERE d.drawn) AS drawn_for,
    string_agg(d.stratum, ' ' ORDER BY d.stratum) AS strata,
    x.flag AS crosswalk_flag, x.candidate_rank, dr.flag AS drainage_flag, fo.flag AS following_flag,
    round((fl.q_fwa / nullif(fl.q_pcic, 0))::numeric, 2) AS fwa_over_pcic_flow,
    (SELECT string_agg(g.station, ' ' ORDER BY g.station) FROM fwapg.pcic_qa_gauges g
     WHERE g.pcic_subid = d.subid AND g.fwa_over_pcic NOT BETWEEN 0.9 AND 1.1 AND NOT g.any_pcic_matches_fwa) AS gauges
  FROM fwapg.pcic_review_design d
  INNER JOIN whse_basemapping.pcic_fwa_crosswalk x ON x.subid = d.subid
  LEFT JOIN fwapg.pcic_qa_drainage dr ON dr.subid = d.subid
  LEFT JOIN fwapg.pcic_qa_following fo ON fo.subid = d.subid
  LEFT JOIN fwapg.pcic_qa_flow fl ON fl.subid = d.subid
  GROUP BY d.review_id, d.subid, x.flag, x.candidate_rank, dr.flag, fo.flag, fl.q_fwa, fl.q_pcic
  ORDER BY d.review_id
) TO '$OUT/flags.csv' WITH (FORMAT csv, HEADER)"

$PSQL -c "DROP TABLE fwapg.pcic_review_rivers, fwapg.pcic_review_lakes"

# checks (ogrinfo without -q: with it, GDAL 3.13 prints no fields): the review layer holds the form and nothing else, every drawn outlet is
# in it once, each stratum drew min(cap, population), and no layer carries an id
# or a flag that would unblind the review
fields=$(ogrinfo -so "$GPKG" review | awk -F: '/^[a-z_]+: /{print $1}' | paste -sd, -)
[ "$fields" = "review_id,verdict,confidence,note" ] || { echo "review layer fields: $fields" >&2; exit 1; }
n=$(ogrinfo -sql 'SELECT count(DISTINCT review_id) AS n, count(*) AS m FROM review' "$GPKG" | awk '/^ *n \(/{n=$NF} /^ *m \(/{m=$NF} END {print n "," m}')
want=$($PSQL -tXA -c "SELECT count(DISTINCT review_id) FROM fwapg.pcic_review_design")
[ "$n" = "$want,$want" ] || { echo "review layer holds $n (distinct, all) review_ids, the design $want" >&2; exit 1; }
short=$($PSQL -tXA -c "
  SELECT string_agg(p.stratum, ' ')
  FROM (SELECT stratum, count(*) AS population FROM fwapg.pcic_review_strata GROUP BY stratum) p
  WHERE (SELECT count(*) FROM fwapg.pcic_review_design d WHERE d.stratum = p.stratum AND d.drawn)
    != least(CASE WHEN p.stratum = 'random' THEN $CAP_RANDOM ELSE $CAP END, p.population)")
[ -z "$short" ] || { echo "strata drawn short of min(cap, population): $short" >&2; exit 1; }
leak=$(ogrinfo -so -al "$GPKG" | awk -F: '/^(subid|dowsubid|stratum|flag|candidate_rank|distance_to_stream|strata|drawn): /' | sort -u)
[ -z "$leak" ] || { echo "review.gpkg carries $leak" >&2; exit 1; }

$PSQL -c "DROP TABLE fwapg.pcic_review_strata"
echo "review: $want outlets in $GPKG (sample_id $sample_id); design in $DESIGN, flags in $OUT/flags.csv"
