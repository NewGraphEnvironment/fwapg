import os, shutil, subprocess, sys
repo, sp = sys.argv[1], sys.argv[2]
X = "extras/pcic_crosswalk/sql/pcic_export.sql"; L = "load/pcic.sql"; R = "load/pcic_run.sql"; RM = "extras/pcic_crosswalk/README.md"; D9 = "extras/pcic_crosswalk/sql/pcic_crosswalk09_discharge.sql"
M = [
 ("Q1 export: daily DELETE keyed on model only", X, "DELETE FROM pcic.subbasin_daily t USING run n WHERE (t.model, t.scenario, t.period) = (n.model, n.scenario, n.period);", "DELETE FROM pcic.subbasin_daily t USING run n WHERE t.model = n.model;"),
 ("Q2 export: monthly DELETE keyed on model only", X, "DELETE FROM pcic.discharge_monthly t USING run n WHERE (t.model, t.scenario, t.period) = (n.model, n.scenario, n.period);", "DELETE FROM pcic.discharge_monthly t USING run n WHERE t.model = n.model;"),
 ("Q3 export: weekly DELETE keyed on model only", X, "DELETE FROM pcic.discharge_weekly t USING run n WHERE (t.model, t.scenario, t.period) = (n.model, n.scenario, n.period);", "DELETE FROM pcic.discharge_weekly t USING run n WHERE t.model = n.model;"),
 ("Q4 export: runs DELETE every row", X, "DELETE FROM pcic.runs t USING run n WHERE (t.model, t.scenario, t.period) = (n.model, n.scenario, n.period);", "DELETE FROM pcic.runs;"),
 ("Q5 export: daily fingerprint over every run", X, "FROM pcic.subbasin_daily t WHERE (t.model, t.scenario, t.period) = (n.model, n.scenario, n.period)\n) d", "FROM pcic.subbasin_daily t\n) d"),
 ("Q6 export: weekly n_rows 0 not NULL", X, "nullif(count(*), 0) AS n_rows", "count(*) AS n_rows"),
 ("Q7 run: DELETE keyed on model only", R, "WHERE (p.model, p.scenario, p.period) = (i.model, i.scenario, i.period);", "WHERE p.model = i.model;"),
 ("Q8 09: upstream sum over every step", D9, "      AND u.:step = m.:step\n", ""),
 ("Q9 09: no coalesce", D9, "    coalesce((\n      SELECT sum(u.q_acc)\n      FROM fwapg.pcic_subbasins_:table u\n      WHERE u.subid = ANY(w.upstream_subids)\n      AND u.:step = m.:step\n    ), 0)", "    (\n      SELECT sum(u.q_acc)\n      FROM fwapg.pcic_subbasins_:table u\n      WHERE u.subid = ANY(w.upstream_subids)\n      AND u.:step = m.:step\n    )"),
 ("Q10 01: last day short", "extras/pcic_crosswalk/sql/pcic_crosswalk01_days.sql", "make_date(:y2, 12, 31)", "make_date(:y2, 12, 30)"),
 ("Q11 load: stale monthly DELETE keyed on model only", L, "DELETE FROM pcic.discharge_monthly t USING runs_in i\n  WHERE (t.model, t.scenario, t.period) = (i.model, i.scenario, i.period)", "DELETE FROM pcic.discharge_monthly t USING runs_in i\n  WHERE t.model = i.model"),
 ("Q12 run: weekly checked against monthly", R, "WHEN 'discharge_weekly' THEN 'weekly'", "WHEN 'discharge_weekly' THEN 'monthly'"),
 ("Q13 export: md5 ordered differently", X, "(SELECT md5(string_agg(x::text, '|' ORDER BY x.subid)) FROM fwapg.pcic_fwa_crosswalk x)", "(SELECT md5(string_agg(x::text, '|' ORDER BY x.linear_feature_id DESC)) FROM fwapg.pcic_fwa_crosswalk x)"),
 ("Q14 README: window misses Feb 29", RM, "make_date(2001, month, least(day, CASE WHEN month = 2 THEN 28 ELSE 31 END))", "make_date(2001, month, CASE WHEN (month, day) = (2, 29) THEN 28 ELSE day END) - CASE WHEN (month, day) = (2, 29) THEN 400 ELSE 0 END"),
 ("Q15 08: outlet joined on month only", "extras/pcic_crosswalk/sql/pcic_crosswalk08_periods.sql", "INNER JOIN fwapg.pcic_day_bins b ON b.month = q.month AND b.day = q.day", "INNER JOIN fwapg.pcic_day_bins b ON b.month = q.month AND b.day = q.day AND b.n_days > 0"),
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
