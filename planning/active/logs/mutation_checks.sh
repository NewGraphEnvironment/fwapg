#!/bin/bash
# #24: restore each defect the diversion code guards against, on the staging tables
# a dev build left at QA, and check that the QA tests meant to catch it read f.
# Each mutation is applied to a copy of the job's SQL, checked to have matched, run
# on the groups it touches, then undone by rerunning the real SQL. M5 runs last and
# is not undone: it replaces the placement, which the next build rebuilds anyway.
#
#   DATABASE_URL=... ./mutation_checks.sh > 20261027_mutation_checks.out 2>&1
set -euo pipefail

JOB=$(cd "$(dirname "$0")/../../../extras/pcic_crosswalk" && pwd)
PSQL="psql $DATABASE_URL -v ON_ERROR_STOP=1 -q"
MUT=$(mktemp -d "${TMPDIR:-/tmp}/pcic_mut.XXXXXX")
trap 'rm -rf "$MUT"' EXIT

# the qa.sql statements whose test names match $1 (an extended regex), run alone
qa() {
  python3 - "$JOB/sql/qa.sql" "$1" > "$MUT/qa_pick.sql" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
for stmt in re.split(r";\s*\n", text):
    body = "\n".join(l for l in stmt.splitlines() if not l.lstrip().startswith("--")).strip()
    m = re.search(r"SELECT '((?:[^']|'')*)' AS test", body)
    if body and m and re.search(sys.argv[2], m.group(1).replace("''", "'")):
        print(body + ";")
PY
  [ -s "$MUT/qa_pick.sql" ] || { echo "no qa.sql test matches $1" >&2; exit 1; }
  $PSQL -tXA -F ' | ' -f "$MUT/qa_pick.sql"
}

# a fresh copy of the job's SQL with one literal edit, refused unless it matches once
mutate() {
  rm -rf "$MUT/sql" && cp -R "$JOB/sql" "$MUT/sql"
  python3 - "$MUT/sql/$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:]
s = open(p).read()
assert s.count(old) == 1, f"mutation does not match once in {p}: {old!r}"
open(p, "w").write(s.replace(old, new))
PY
}

# weights and monthly flow of the groups in $2, from the SQL in $1
segments() {
  for wsg in $2; do
    $PSQL -c "DELETE FROM fwapg.pcic_segment_weights WHERE watershed_group_code = '$wsg'"
    $PSQL -v wsg="$wsg" -f "$1/pcic_crosswalk07_segments.sql"
    $PSQL -c "DELETE FROM fwapg.pcic_discharge_monthly WHERE watershed_group_code = '$wsg'"
    $PSQL -v wsg="$wsg" -v step=month -v table=monthly -f "$1/pcic_crosswalk09_discharge.sql"
  done
}

NECHAKO="LEUT UEUT UNRS LNRS CHES"
TESTS='diversion|Nechako|Eutsuk|outlet segments carry|area comes off'

echo "== base (dev build staging, real SQL) $(date -u +%H:%M:%SZ)"
qa "$TESTS"

echo "== M1: 07 does not add the diverted outlet at its PCIC ancestor's segment $(date -u +%H:%M:%SZ)"
mutate pcic_crosswalk07_segments.sql "    || CASE WHEN s.linear_feature_id = sb.linear_feature_id THEN
      coalesce((SELECT array_agg(d.subid ORDER BY d.subid) FROM outlets d WHERE d.diverted AND d.fwa_parent_subid = s.subid), '{}')
    ELSE '{}' END AS upstream_subids," "    AS upstream_subids,"
segments "$MUT/sql" CHES
qa 'outlet segments carry|Nechako Reservoir weights|exactly one segment|spillway 1008709'
segments "$JOB/sql" CHES

echo "== M2: 07 joins children by flow parent, not position $(date -u +%H:%M:%SZ)"
mutate pcic_crosswalk07_segments.sql "  ON c.area_parent_subid = s.subid" "  ON c.fwa_parent_subid = s.subid"
segments "$MUT/sql" LNRS
qa 'Nechako Reservoir weights|canyon'
segments "$JOB/sql" LNRS

echo "== M3: 06 takes a diversion's area off its flow parent $(date -u +%H:%M:%SZ)"
mutate pcic_crosswalk06_subbasins.sql "    coalesce(dv.position_parent_subid, x.fwa_parent_subid) AS fwa_parent_subid," "    x.fwa_parent_subid AS fwa_parent_subid,"
$PSQL -f "$MUT/sql/pcic_crosswalk06_subbasins.sql"
qa 'area comes off'
$PSQL -f "$JOB/sql/pcic_crosswalk06_subbasins.sql"

echo "== M4: 06 leaves a diversion's flow on its position parent $(date -u +%H:%M:%SZ)"
mutate pcic_crosswalk06_subbasins.sql "SET fwa_parent_subid = x.anchor_subid
FROM fwapg.pcic_diversions dv" "SET fwa_parent_subid = x.fwa_parent_subid
FROM fwapg.pcic_diversions dv"
$PSQL -f "$MUT/sql/pcic_crosswalk06_subbasins.sql" || echo "(06 refused)"
qa 'every diversion is placed'
$PSQL -f "$JOB/sql/pcic_crosswalk06_subbasins.sql"

echo "== base again, after the undo $(date -u +%H:%M:%SZ)"
qa "$TESTS"

echo "== M5: no diversion listed; placement rerun $(date -u +%H:%M:%SZ)"
$PSQL -c "DELETE FROM fwapg.pcic_diversions"
# as pcic_crosswalk03_prepare.sql leaves it: 05 counts this round's demotions by round
$PSQL -c "TRUNCATE fwapg.pcic_demoted"
for round in $(seq 1 10); do
  $PSQL -f "$JOB/sql/pcic_crosswalk04_select.sql"
  n=$($PSQL -tXA -v round=$round -f "$JOB/sql/pcic_crosswalk05_demote.sql")
  [ "$n" -eq 0 ] && break
done
qa 'every diversion is placed|Nechako Reservoir groups'
echo "== done $(date -u +%H:%M:%SZ)"
