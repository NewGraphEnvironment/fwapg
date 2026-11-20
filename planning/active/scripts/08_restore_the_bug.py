"""fwapg#4: restore the defect each area test guards and see the test print f.

Each case runs BEGIN; <mutation>; <the test's own statement from qa.sql>; ROLLBACK
in one psql session, so nothing is left changed. Usage, from the repo root, with
DATABASE_URL set:  python3 planning/active/scripts/08_restore_the_bug.py
"""
import os
import re
import subprocess
import sys

QA = "extras/mainflow_tree/sql/qa.sql"
TREE = "whse_basemapping.fwa_stream_networks_mainflow_tree"
AREA = "fwapg.mainflow_tree_area"
QA_T = "fwapg.mainflow_tree_area_qa"

# (words from the test's name, the defect restored)
CASES = [
    ("every tree segment has a positive upstream area",
     f"UPDATE {TREE} SET upstream_area_ha = NULL WHERE linear_feature_id = 87078680"),
    # the column on the tree no longer what the build's own table holds
    ("every tree segment has a positive upstream area",
     f"UPDATE {TREE} SET upstream_area_ha = upstream_area_ha + 1 WHERE linear_feature_id = 87078680"),
    ("area is additive at every node",
     f"UPDATE {AREA} SET upstream_area_ha = upstream_area_ha + 1 WHERE linear_feature_id = 123039830"),
    ("area never decreases downstream along a blue line",
     f"UPDATE {TREE} SET upstream_area_ha = upstream_area_ha * 2 WHERE linear_feature_id = 245024871"),
    ("areas sum to the area assigned",
     f"UPDATE {AREA} SET upstream_area_ha = upstream_area_ha + 1000 WHERE linear_feature_id = "
     f"(SELECT min(linear_feature_id) FROM {AREA} WHERE downstream_id IS NULL)"),
    ("every unassigned polygon has a class",
     "UPDATE fwapg.mainflow_tree_area_unassigned SET class = NULL WHERE watershed_feature_id = "
     "(SELECT min(watershed_feature_id) FROM fwapg.mainflow_tree_area_unassigned)"),
    ("steps across a gap start at dead ends and cut-offs only",
     f"UPDATE {AREA} SET downstream_method = 'junction' WHERE linear_feature_id = 87078680"),
    ("the Skeena and the Nechako carry the polygons under their code",
     f"UPDATE {TREE} t SET upstream_area_ha = t.upstream_area_ha * 1.01 FROM whse_basemapping.fwa_stream_networks_sp s "
     "WHERE s.linear_feature_id = t.linear_feature_id AND s.wscode_ltree = '400' "
     "AND s.blue_line_key = s.watershed_key AND s.downstream_route_measure = 0"),
    # the defect the issue is about: the lookup's area on a side channel
    ("four Skeena side channels carry the area of the tributary",
     f"UPDATE {TREE} SET upstream_area_ha = 5059365 WHERE linear_feature_id = 123039830"),
    ("a tributary mouth inside its river",
     f"UPDATE {TREE} SET upstream_area_ha = 4558110 WHERE linear_feature_id = 87078680"),
    # round 1's second finding: a fallback rule putting a polygon on a side channel
    ("every polygon is on a segment its rule allows",
     "UPDATE fwapg.mainflow_tree_area_polygons SET linear_feature_id = 123039830 WHERE watershed_feature_id = "
     "(SELECT min(watershed_feature_id) FROM fwapg.mainflow_tree_area_polygons WHERE method = 'lower')"),
    ("at most 97 steps across a gap and 803 segments given a length share",
     f"INSERT INTO fwapg.mainflow_tree_area_shares SELECT linear_feature_id, NULL, 1 FROM {AREA} "
     "WHERE shared_area_ha IS NULL LIMIT 1"),
    ("main flow agrees with the lookup where nothing upstream is routed differently",
     f"UPDATE {QA_T} SET class = NULL WHERE linear_feature_id = "
     f"(SELECT min(linear_feature_id) FROM {QA_T} WHERE class = 'side channel')"),
    ("the lookup differs on side channels and where the tree routes differently",
     f"DELETE FROM {QA_T} WHERE source != 'mainflow'"),
    ("the classes that are not about routing are no larger than measured",
     f"UPDATE {QA_T} SET class = 'local codes out of order' WHERE linear_feature_id = "
     f"(SELECT min(linear_feature_id) FROM {QA_T} WHERE class = 'side channel')"),
]

text = open(QA).read()
# a statement runs from after the previous ';' at a line end to its own
statements = [s.strip() for s in re.split(r";[ \t]*\n", text) if "AS test" in s]
url = os.environ["DATABASE_URL"]
bad = 0
for words, mutation in CASES:
    found = [s for s in statements if words in s.replace("''", "'")]
    if len(found) != 1:
        print(f"NO SINGLE TEST for: {words} ({len(found)})")
        bad += 1
        continue
    sql = f"BEGIN;\n{mutation};\n{found[0]};\nROLLBACK;\n"
    out = subprocess.run(["psql", url, "-tXA", "-v", "ON_ERROR_STOP=1"], input=sql, capture_output=True, text=True)
    lines = [l for l in out.stdout.splitlines() if "|" in l]
    result = lines[-1].rsplit("|", 1)[1] if lines else f"no line (psql exit {out.returncode}: {out.stderr.strip()[:120]})"
    moved = [l for l in out.stdout.splitlines() if re.match(r"^(UPDATE|DELETE|INSERT)", l)]
    print(f"{'fires' if result == 'f' else 'DOES NOT FIRE'}|{result}|{' '.join(moved)}|{words}")
    if result != "f":
        bad += 1
sys.exit(1 if bad else 0)
