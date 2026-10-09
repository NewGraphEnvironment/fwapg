#!/bin/bash
set -euxo pipefail

# Main-flow tree: a dendritic subset of the FWA stream network. See README.md.

cd "$(dirname "$0")"
PSQL="psql $DATABASE_URL -v ON_ERROR_STOP=1"

mkdir -p data

# downstream path of every blue line: which side channels each line drains through
../blue_line_paths/blue_line_paths.sh

# segments excluded or included by hand
$PSQL -c "DROP TABLE IF EXISTS fwapg.mainflow_tree_overrides"
$PSQL -c "CREATE TABLE fwapg.mainflow_tree_overrides (linear_feature_id bigint PRIMARY KEY, action text NOT NULL CHECK (action IN ('exclude', 'include')), note text)"
$PSQL -c "\copy fwapg.mainflow_tree_overrides FROM STDIN WITH (FORMAT csv, HEADER)" < overrides.csv

$PSQL -f sql/mainflow_tree.sql

# splits and cut-offs, tested in qa.sql and kept for review
$PSQL -f sql/qa_topology.sql
$PSQL -c "\copy (SELECT * FROM fwapg.mainflow_tree_qa ORDER BY kind, watershed_group_code, blue_line_key, downstream_route_measure) TO 'data/qa_topology.csv' WITH (FORMAT csv, HEADER)"

# a NULL result (a test over no rows) prints "name|" and fails too
qa=$($PSQL -tXA -f sql/qa.sql)
echo "$qa"
if [ -z "$qa" ] || grep -qv '|t$' <<< "$qa"; then
  echo "QA failed, see sql/qa.sql; nothing exported" >&2
  exit 1
fi

$PSQL -c "\copy (SELECT * FROM whse_basemapping.fwa_stream_networks_mainflow_tree ORDER BY linear_feature_id) TO 'fwa_stream_networks_mainflow_tree.csv' WITH (FORMAT csv, HEADER)"
gzip -f fwa_stream_networks_mainflow_tree.csv
echo 'main-flow tree complete, see whse_basemapping.fwa_stream_networks_mainflow_tree'
