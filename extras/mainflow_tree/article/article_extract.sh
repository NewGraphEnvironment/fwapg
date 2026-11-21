#!/bin/bash
# Write the article's extracts from a database holding the main-flow tree and
# its upstream area (../mainflow_tree.sh), into extracts/. Each case's sql/<case>.sql
# names the segments and polygons it shows; the streams and polygons queries
# below add their attributes. GeoJSON in EPSG:4326 at 6 decimals, rows in
# id order, so a re-extract of the same build writes the same files.
#
#   DATABASE_URL=postgresql://... ./article_extract.sh
set -euo pipefail

: "${DATABASE_URL:?set DATABASE_URL to the database holding the main-flow tree}"
cd "$(dirname "$0")" || exit 1
mkdir -p extracts
# BC Albers (NAD83) to lat/lon with no datum shift (as projinfo writes it, in
# EPSG:4326 axis order, which GDAL turns to lon/lat), the operation PROJ ranks
# best for BC; given explicitly because GDAL otherwise picks per feature, and
# a ballpark step outside an operation's area of use (case 5, SHEK) warns
CT="+proj=pipeline +step +inv +proj=aea +lat_0=45 +lon_0=-126 +lat_1=50 +lat_2=58.5 +x_0=1000000 +y_0=0 +ellps=GRS80 +step +proj=unitconvert +xy_in=rad +xy_out=deg +step +proj=axisswap +order=2,1"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/article_extract.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

# the build the article describes: 2026-11, 1,898 share rows and 123039830 at 53,007 ha
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -Atq -c "
  SELECT CASE WHEN (SELECT count(*) FROM fwapg.mainflow_tree_area_shares) = 1898
    AND (SELECT round(upstream_area_ha) FROM fwapg.mainflow_tree_area WHERE linear_feature_id = 123039830) = 53007
  THEN 'build ok' ELSE 'build differs' END" | grep -qx 'build ok' \
  || { echo "REFUSE: the database's area build is not the one the article describes"; exit 1; }

STREAMS="
SELECT s.linear_feature_id, s.blue_line_key, s.gnis_name, s.edge_type,
  s.wscode_ltree::text AS wscode, s.localcode_ltree::text AS localcode,
  t.linear_feature_id IS NOT NULL AS tree, t.source,
  a.upstream_area_ha, a.local_area_ha, a.shared_area_ha, a.downstream_id, a.downstream_method,
  ua.upstream_area_ha AS lookup_area_ha, q.kind AS qa_kind, ss.focus,
  ST_Force2D(s.geom) AS geom
FROM seg_set ss
INNER JOIN whse_basemapping.fwa_stream_networks_sp s ON s.linear_feature_id = ss.linear_feature_id
LEFT JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t ON t.linear_feature_id = s.linear_feature_id
LEFT JOIN fwapg.mainflow_tree_area a ON a.linear_feature_id = s.linear_feature_id
LEFT JOIN whse_basemapping.fwa_streams_watersheds_lut l ON l.linear_feature_id = s.linear_feature_id
LEFT JOIN whse_basemapping.fwa_watersheds_upstream_area ua ON ua.watershed_feature_id = l.watershed_feature_id
LEFT JOIN fwapg.mainflow_tree_qa q ON q.linear_feature_id = s.linear_feature_id
ORDER BY s.linear_feature_id"

POLYS="
SELECT w.watershed_feature_id, w.watershed_group_code, w.wscode_ltree::text AS wscode,
  w.localcode_ltree::text AS localcode, p.method, p.linear_feature_id,
  s.blue_line_key AS assigned_blue_line_key, p.area_ha, p.shared_ha,
  ps.kind, ps.focus, ps.moved, w.geom
FROM poly_set ps
INNER JOIN whse_basemapping.fwa_watersheds_poly w ON w.watershed_feature_id = ps.watershed_feature_id
LEFT JOIN fwapg.mainflow_tree_area_polygons p ON p.watershed_feature_id = w.watershed_feature_id
LEFT JOIN whse_basemapping.fwa_stream_networks_sp s ON s.linear_feature_id = p.linear_feature_id
ORDER BY w.watershed_feature_id"

geojson() {  # <out> <sql file>
  rm -f "$1"
  ogr2ogr -f GeoJSON -s_srs EPSG:3005 -t_srs EPSG:4326 -ct "$CT" -lco COORDINATE_PRECISION=6 -lco WRITE_NAME=NO \
    "$1" PG:"$DATABASE_URL" -sql @"$2"
  [ -s "$1" ] || { echo "REFUSE: $1 is empty"; exit 1; }
}

for c in case1 case2 case3 case4 case5 case6 case7; do
  { echo "WITH"; cat "sql/$c.sql"; echo "$STREAMS"; } > "$TMP/${c}_streams.sql"
  { echo "WITH"; cat "sql/$c.sql"; echo "$POLYS"; } > "$TMP/${c}_polygons.sql"
  geojson "extracts/${c}_streams.geojson" "$TMP/${c}_streams.sql"
  geojson "extracts/${c}_polygons.geojson" "$TMP/${c}_polygons.sql"
  echo "$c: $(grep -o '"type":"Feature"' "extracts/${c}_streams.geojson" | wc -l | tr -d ' ') streams, $(grep -o '"type":"Feature"' "extracts/${c}_polygons.geojson" | wc -l | tr -d ' ') polygons"
done

# case 5: every share its polygon gives, wherever the segment lies
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -c "\copy (
  SELECT x.linear_feature_id, x.watershed_feature_id, x.share_ha
  FROM fwapg.mainflow_tree_area_shares x
  WHERE x.watershed_feature_id = 8442664
  ORDER BY x.linear_feature_id) TO 'extracts/case5_shares.csv' WITH (FORMAT csv, HEADER)"

# the chart: the share of the confluence a side channel takes, tree and lookup
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -c "\copy ($(sed -e 's/--.*//' -e 's/;[[:space:]]*$//' sql/confluence_share.sql | tr '\n' ' ')) TO 'extracts/confluence_share.csv' WITH (FORMAT csv, HEADER)"

# case 3: mapped floodplain (stac-floodplains-bc, item morr_all_ff04, layer
# all_ff04, both sides of the group boundary), clipped to the case's view
FP=/vsicurl/https://stac-floodplains-bc.s3.us-west-2.amazonaws.com/morr_all_ff04/floodplain.gpkg
BBOX=$(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -Atq -F ' ' -c "WITH $(cat sql/case3.sql)
  SELECT ST_XMin(geom), ST_YMin(geom), ST_XMax(geom), ST_YMax(geom) FROM view")
[ "$(echo "$BBOX" | wc -w | tr -d ' ')" = 4 ] || { echo "REFUSE: no case-3 view"; exit 1; }
# the layer is in EPSG:3005, as the view is
rm -f extracts/case3_floodplain.geojson
# shellcheck disable=SC2086
GDAL_DISABLE_READDIR_ON_OPEN=EMPTY_DIR ogr2ogr -f GeoJSON -t_srs EPSG:4326 -ct "$CT" -lco COORDINATE_PRECISION=6 \
  -lco WRITE_NAME=NO -spat $BBOX -clipsrc $BBOX -select wsg,in_wsg,scenario \
  extracts/case3_floodplain.geojson "$FP" all_ff04
[ -s extracts/case3_floodplain.geojson ] || { echo "REFUSE: no floodplain written for case 3"; exit 1; }
echo "case3 floodplain: $(grep -o '"type":"Feature"' extracts/case3_floodplain.geojson | wc -l | tr -d ' ') features"

du -ch extracts/* | tail -1
