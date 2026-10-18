import os, shutil, subprocess, sys
repo, sp = sys.argv[1], sys.argv[2]
X = "extras/pcic_crosswalk/sql/pcic_export.sql"; L = "load/pcic.sql"; R = "load/pcic_run.sql"; RM = "extras/pcic_crosswalk/README.md"; D9 = "extras/pcic_crosswalk/sql/pcic_crosswalk09_discharge.sql"
M = [
 ("R1 README: q_acc unweighted", RM, "sum(q_acc * n_days) / sum(n_days) AS q_acc", "avg(q_acc) AS q_acc"),
 ("R2 README: no coalesce", RM, "greatest(coalesce((SELECT sum(u.q_acc) FROM window_flow u WHERE u.subid = ANY(w.upstream_subids)), 0)", "greatest((SELECT sum(u.q_acc) FROM window_flow u WHERE u.subid = ANY(w.upstream_subids))"),
 ("R3 run: daily sum over q_local", R, "CASE prefix WHEN 'daily' THEN 'q_acc' ELSE 'q_m3s' END", "CASE prefix WHEN 'daily' THEN 'q_local' ELSE 'q_m3s' END"),
]
only = set(sys.argv[3:])
for name, f, a, b in M:
    if only and name.split()[0] not in only: continue
    d = os.path.join(sp, "mutrev3")
    shutil.rmtree(d, ignore_errors=True)
    for sub in ("extras/pcic_crosswalk", "load"):
        shutil.copytree(os.path.join(repo, sub), os.path.join(d, sub), ignore=shutil.ignore_patterns("data"))
    p = os.path.join(d, f); s = open(p).read()
    if s.count(a) != 1: print(f"NOT APPLIED ({s.count(a)})  {name}", flush=True); continue
    open(p, "w").write(s.replace(a, b, 1))
    r = subprocess.run(["bash", os.path.join(d, "extras/pcic_crosswalk/pcic_test.sh")], capture_output=True, text=True, env=dict(os.environ, PGSERVER="postgresql://postgres:postgres@localhost:5432"))
    fl = [l for l in r.stdout.splitlines() if l.startswith(("FAIL", "ABORTED"))]
    print(f"{'caught' if r.returncode and fl else 'MISSED'}  exit {r.returncode}  {name}: {fl[0][:110] if fl else ''}", flush=True)
