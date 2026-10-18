import os, shutil, subprocess, sys
repo, sp = sys.argv[1], sys.argv[2]
X = "extras/pcic_crosswalk/sql/pcic_export.sql"; L = "load/pcic.sql"; R = "load/pcic_run.sql"; RM = "extras/pcic_crosswalk/README.md"; D9 = "extras/pcic_crosswalk/sql/pcic_crosswalk09_discharge.sql"
M = [
 ("A run: fingerprint ignores the sum", R, "IF (got_rows, got_keys, got_sum) IS DISTINCT FROM (want_rows, want_keys, want_sum)", "IF (got_rows, got_keys) IS DISTINCT FROM (want_rows, want_keys)"),
 ("B run: fingerprint ignores keys", R, "IF (got_rows, got_keys, got_sum) IS DISTINCT FROM (want_rows, want_keys, want_sum)", "IF (got_rows, got_sum) IS DISTINCT FROM (want_rows, want_sum)"),
 ("B2 run: fingerprint ignores rows", R, "IF (got_rows, got_keys, got_sum) IS DISTINCT FROM (want_rows, want_keys, want_sum)", "IF (got_keys, got_sum) IS DISTINCT FROM (want_keys, want_sum)"),
 ("C load: weights check ignores rows", L, "WHERE weights_rows IS DISTINCT FROM w_rows OR weights_share_sum IS DISTINCT FROM w_sum", "WHERE weights_share_sum IS DISTINCT FROM w_sum"),
 ("C2 load: weights check ignores sum", L, "WHERE weights_rows IS DISTINCT FROM w_rows OR weights_share_sum IS DISTINCT FROM w_sum", "WHERE weights_rows IS DISTINCT FROM w_rows"),
 ("D export: other ignores weights_rows", X, "AND (r.crosswalk_md5, r.weights_rows, r.weights_share_sum)\n    IS DISTINCT FROM (n.crosswalk_md5, n.weights_rows, n.weights_share_sum)", "AND (r.crosswalk_md5, r.weights_share_sum)\n    IS DISTINCT FROM (n.crosswalk_md5, n.weights_share_sum)"),
 ("E load: other ignores crosswalk", L, "AND (r.crosswalk_md5, r.weights_rows, r.weights_share_sum) IS DISTINCT FROM (cw_md5, w_rows, w_sum)", "AND (r.weights_rows, r.weights_share_sum) IS DISTINCT FROM (w_rows, w_sum)"),
 ("E2 load: other ignores weights", L, "AND (r.crosswalk_md5, r.weights_rows, r.weights_share_sum) IS DISTINCT FROM (cw_md5, w_rows, w_sum)", "AND r.crosswalk_md5 IS DISTINCT FROM cw_md5"),
 ("F load: deletes every pcic.runs row", L, "DELETE FROM pcic.runs r USING runs_in i WHERE (i.model, i.scenario, i.period) = (r.model, r.scenario, r.period);", "DELETE FROM pcic.runs;"),
 ("G load: stale weekly DELETE keyed on model only", L, "DELETE FROM pcic.discharge_weekly t USING runs_in i\n  WHERE (t.model, t.scenario, t.period) = (i.model, i.scenario, i.period)", "DELETE FROM pcic.discharge_weekly t USING runs_in i\n  WHERE t.model = i.model"),
 ("G2 load: stale daily DELETE keyed on model only", L, "DELETE FROM pcic.subbasin_daily t USING runs_in i\n  WHERE (t.model, t.scenario, t.period) = (i.model, i.scenario, i.period)", "DELETE FROM pcic.subbasin_daily t USING runs_in i\n  WHERE t.model = i.model"),
 ("H README: window ignores the run", RM, "  WHERE (model, scenario, period) = ('PNWNAmet', 'historical', '1981-2010')\n  AND make_date", "  WHERE make_date"),
 ("I export: weekly_segments 0, not NULL", X, "nullif(count(DISTINCT linear_feature_id), 0) AS n_keys", "count(DISTINCT linear_feature_id) AS n_keys"),
 ("J load: stale monthly ignores rows and segments", L, "AND (r.crosswalk_md5, r.monthly_rows, r.monthly_segments, r.monthly_q_sum)\n      IS NOT DISTINCT FROM (i.crosswalk_md5, i.monthly_rows, i.monthly_segments, i.monthly_q_sum)", "AND (r.crosswalk_md5, r.monthly_q_sum)\n      IS NOT DISTINCT FROM (i.crosswalk_md5, i.monthly_q_sum)"),
 ("K run: fingerprint lookup on model only", R, "WHERE (r.model, r.scenario, r.period) = (SELECT DISTINCT model, scenario, period FROM incoming)'", "WHERE r.model = (SELECT DISTINCT model FROM incoming)'"),
 ("L 09: no wsg filter", D9, "WHERE w.watershed_group_code = :'wsg'", "WHERE true"),
 ("M README: no wsg filter", RM, "WHERE w.watershed_group_code = 'BULK';", "WHERE true;"),
 ("N load: md5 check any-run not every-run", L, "IF EXISTS (SELECT 1 FROM runs_in WHERE crosswalk_md5 IS DISTINCT FROM cw_md5) THEN", "IF NOT EXISTS (SELECT 1 FROM runs_in WHERE crosswalk_md5 = cw_md5) THEN"),
 ("O load: weights check any-run not every-run", L, "IF EXISTS (SELECT 1 FROM runs_in WHERE weights_rows IS DISTINCT FROM w_rows OR weights_share_sum IS DISTINCT FROM w_sum) THEN", "IF NOT EXISTS (SELECT 1 FROM runs_in WHERE weights_rows = w_rows AND weights_share_sum = w_sum) THEN"),
 ("P export: other ignores share sum", X, "AND (r.crosswalk_md5, r.weights_rows, r.weights_share_sum)\n    IS DISTINCT FROM (n.crosswalk_md5, n.weights_rows, n.weights_share_sum)", "AND (r.crosswalk_md5, r.weights_rows)\n    IS DISTINCT FROM (n.crosswalk_md5, n.weights_rows)"),
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
