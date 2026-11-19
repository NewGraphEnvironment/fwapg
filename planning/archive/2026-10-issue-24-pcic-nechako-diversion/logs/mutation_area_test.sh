#!/bin/bash
# #24: prove qa.sql's area test (rewritten in code-check rounds 2 and 3) fires. The
# staging tables it reads are dropped at the end of a build, so this rebuilds them in
# a scratch schema from the published pcic.fwa_crosswalk and the kept
# fwapg.pcic_qa_diversions, takes local area with 06's own statement, then with three
# wrong ones, and runs the test on each. Expect t, then f, f, f.
#
#   DATABASE_URL=... ./mutation_area_test.sh > 20261027_mutation_area_test.out 2>&1
set -euo pipefail

JOB=$(cd "$(dirname "$0")/../../../../extras/pcic_crosswalk" && pwd)
PSQL="psql $DATABASE_URL -v ON_ERROR_STOP=1 -q"
MUT=$(mktemp -d "${TMPDIR:-/tmp}/pcic_mut.XXXXXX")
trap 'rm -rf "$MUT"; $PSQL -c "DROP SCHEMA IF EXISTS mut24 CASCADE"' EXIT

# 06's area statement, the CREATE TABLE fwapg.pcic_subbasins up to its ALTER, and the
# area test, each pointed at the scratch schema
python3 - "$JOB/sql" "$MUT" <<'PY'
import re, sys
sql, out = sys.argv[1:]
s = open(f"{sql}/pcic_crosswalk06_subbasins.sql").read()
i = s.index("CREATE TABLE fwapg.pcic_subbasins AS")
j = s.index("ALTER TABLE fwapg.pcic_subbasins ADD PRIMARY KEY")
area = s[i:j].replace("fwapg.pcic_", "mut24.pcic_")
assert area.count("coalesce(dv.position_parent_subid, x.fwa_parent_subid) AS fwa_parent_subid") == 1
open(f"{out}/area.sql", "w").write(area)
q = open(f"{sql}/qa.sql").read()
picks = [st for st in re.split(r";\s*\n", q) if "area comes off its position parent" in st]
assert len(picks) == 1, len(picks)
body = "\n".join(l for l in picks[0].splitlines() if not l.lstrip().startswith("--")).strip()
open(f"{out}/test.sql", "w").write(body.replace("fwapg.pcic_", "mut24.pcic_") + ";\n")
PY

$PSQL <<'SQL'
DROP SCHEMA IF EXISTS mut24 CASCADE;
CREATE SCHEMA mut24;
CREATE TABLE mut24.pcic_fwa_crosswalk AS SELECT * FROM pcic.fwa_crosswalk;
CREATE TABLE mut24.pcic_diversions AS SELECT * FROM fwapg.pcic_qa_diversions;
SQL

run() {
  echo "== $1 $(date -u +%H:%M:%SZ)"
  $PSQL -c "DROP TABLE IF EXISTS mut24.pcic_subbasins"
  $PSQL -f "$2"
  $PSQL -tXA -c "SELECT d.subid, d.position_parent_subid, x.fwa_parent_subid,
      round(p.local_area_ha::numeric, 1) AS position_parent_local_ha,
      round(r.local_area_ha::numeric, 1) AS flow_parent_local_ha
    FROM mut24.pcic_diversions d
    JOIN mut24.pcic_fwa_crosswalk x USING (subid)
    JOIN mut24.pcic_subbasins p ON p.subid = d.position_parent_subid
    JOIN mut24.pcic_subbasins r ON r.subid = x.fwa_parent_subid"
  $PSQL -tXA -f "$MUT/test.sql"
}

# a copy of area.sql with one literal edit, refused unless it matches once
mutate() {
  python3 - "$MUT/area.sql" "$MUT/$1" "$2" "$3" <<'PY'
import sys
src, dst, old, new = sys.argv[1:]
s = open(src).read()
assert s.count(old) == 1, f"mutation does not match once: {old!r}"
open(dst, "w").write(s.replace(old, new))
PY
}

C="coalesce(dv.position_parent_subid, x.fwa_parent_subid) AS fwa_parent_subid"
run "real: 06's area statement" "$MUT/area.sql"

mutate a1.sql "$C" "x.fwa_parent_subid AS fwa_parent_subid"
run "A1: the diversion's area comes off its flow parent" "$MUT/a1.sql"

mutate a2.sql "$C" "CASE WHEN dv.subid IS NULL THEN x.fwa_parent_subid END AS fwa_parent_subid"
run "A2: the diversion's area comes off neither" "$MUT/a2.sql"

# off both: the area rows gain a second row for the diversion, parented on its flow parent
mutate a3.sql "  LEFT JOIN mut24.pcic_diversions dv ON dv.subid = x.subid
  WHERE x.flag IS NULL
)" "  LEFT JOIN mut24.pcic_diversions dv ON dv.subid = x.subid
  WHERE x.flag IS NULL
), area AS (
  SELECT * FROM area0
  UNION ALL
  SELECT a.subid, x.fwa_parent_subid, NULL, a.upstream_area_ha
  FROM area0 a JOIN mut24.pcic_diversions dv USING (subid) JOIN mut24.pcic_fwa_crosswalk x USING (subid)
)"
sed -i.bak 's/^WITH area AS (/WITH area0 AS (/' "$MUT/a3.sql"
grep -q '^WITH area0 AS (' "$MUT/a3.sql"
run "A3: the diversion's area comes off both" "$MUT/a3.sql"
echo "== done $(date -u +%H:%M:%SZ)"
