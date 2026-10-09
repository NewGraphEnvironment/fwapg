#!/bin/bash
set -euxo pipefail

# Downstream path of every FWA blue line (fwapg.blk_parents, fwapg.blk_paths,
# fwapg.blk_on_or_upstream). See README.md. Rebuilt by each job that uses it.

cd "$(dirname "$0")"
PSQL="psql $DATABASE_URL -v ON_ERROR_STOP=1"

$PSQL -f sql/blue_line_paths.sql

# a NULL result (a test over no rows) prints "name|" and fails too
qa=$($PSQL -tXA -f sql/qa.sql)
echo "$qa"
if [ -z "$qa" ] || grep -qv '|t$' <<< "$qa"; then
  echo "blue line paths QA failed, see sql/qa.sql" >&2
  exit 1
fi
