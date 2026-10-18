import os, shutil, subprocess, sys
repo, sp = sys.argv[1], sys.argv[2]
M = [
 ("week cap 53", "extras/pcic_crosswalk/sql/pcic_crosswalk01_days.sql", "/ 7 + 1, 52)", "/ 7 + 1, 53)"),
 ("Feb 29 not folded onto Feb 28", "extras/pcic_crosswalk/sql/pcic_crosswalk01_days.sql", "least(c.day, CASE WHEN c.month = 2 THEN 28 ELSE 31 END)", "least(c.day, 31)"),
 ("no-day bins get 1", "extras/pcic_crosswalk/sql/pcic_crosswalk01_days.sql", "coalesce(d.n_days, 0)", "coalesce(d.n_days, 1)"),
 ("unweighted sub-basin mean", "extras/pcic_crosswalk/sql/pcic_crosswalk08_periods.sql", "sum(d.q_local * b.n_days) / sum(b.n_days)", "avg(d.q_local)"),
 ("unweighted outlet mean", "extras/pcic_crosswalk/sql/pcic_crosswalk08_periods.sql", "sum(q.q_m3s * b.n_days) / sum(b.n_days)", "avg(q.q_m3s)"),
 ("no clamp", "extras/pcic_crosswalk/sql/pcic_crosswalk09_discharge.sql", "round(greatest(r.q, 0)::numeric, 5)", "round(r.q::numeric, 5)"),
 ("upstream ignored", "extras/pcic_crosswalk/sql/pcic_crosswalk09_discharge.sql", "WHERE u.subid = ANY(w.upstream_subids)", "WHERE u.subid = w.upstream_subids[1]"),
 ("export: no crosswalk guard", "extras/pcic_crosswalk/sql/pcic_export.sql", "  IF other IS NOT NULL THEN", "  IF false THEN"),
 ("export: no orphan guard", "extras/pcic_crosswalk/sql/pcic_export.sql", "  IF orphan IS NOT NULL THEN", "  IF false THEN"),
 ("export: weekly rows kept", "extras/pcic_crosswalk/sql/pcic_export.sql", "DELETE FROM pcic.discharge_weekly t USING run n WHERE (t.model, t.scenario, t.period) = (n.model, n.scenario, n.period);", "SELECT 1;"),
 ("Feb 29 takes Mar 1's week (leap-year doy)", "extras/pcic_crosswalk/sql/pcic_crosswalk01_days.sql", "make_date(2001, c.month", "make_date(2000, c.month"),
 ("load_run: no fingerprint check", "load/pcic_run.sql", "IF (got_rows, got_keys, got_sum) IS DISTINCT FROM", "IF false AND (got_rows, got_keys, got_sum) IS DISTINCT FROM"),
 ("load_run: plain HEADER", "load/pcic_run.sql", "with (format csv, header match)", "with (format csv, header)"),
 ("load_run: no run check", "load/pcic_run.sql", "IF want_md5 IS NULL THEN", "IF false THEN"),
 ("load: no md5 check", "load/pcic.sql", "WHERE crosswalk_md5 IS DISTINCT FROM cw_md5", "WHERE false"),
 ("load: no orphan check", "load/pcic.sql", "IF orphan IS NOT NULL THEN", "IF false THEN"),
 ("load: stale monthly kept", "load/pcic.sql", "DELETE FROM pcic.discharge_monthly t USING runs_in i\n  WHERE", "DELETE FROM pcic.discharge_monthly t USING runs_in i\n  WHERE false AND"),
 ("README: window unweighted", "extras/pcic_crosswalk/README.md", "sum(q_local * n_days) / sum(n_days) AS q_local", "avg(q_local) AS q_local"),
 ("README: window clamp dropped", "extras/pcic_crosswalk/README.md", "  greatest(coalesce(", "  (coalesce("),
 ("load: no weights check", "load/pcic.sql", "WHERE weights_rows IS DISTINCT FROM w_rows OR weights_share_sum IS DISTINCT FROM w_sum", "WHERE false"),
 ("load: no day-bins check", "load/pcic.sql", "IF (SELECT count(*) FROM day_bins_in) != 366 THEN", "IF false THEN"),
 ("load: no empty-runs check", "load/pcic.sql", "IF NOT EXISTS (SELECT 1 FROM runs_in) THEN", "IF false THEN"),
 ("load: no other-runs check", "load/pcic.sql", "    IF other IS NOT NULL THEN", "    IF false THEN"),
 ("load_run: no one-run check", "load/pcic_run.sql", "IF n != 1 THEN", "IF false THEN"),
 ("load_run: no crosswalk check", "load/pcic_run.sql", "IF want_md5 IS DISTINCT FROM", "IF false AND want_md5 IS DISTINCT FROM"),
 ("09: upstream q_local for q_acc", "extras/pcic_crosswalk/sql/pcic_crosswalk09_discharge.sql", "SELECT sum(u.q_acc)", "SELECT sum(u.q_local)"),
 ("README: upstream q_local for q_acc", "extras/pcic_crosswalk/README.md", "SELECT sum(u.q_acc) FROM window_flow u", "SELECT sum(u.q_local) FROM window_flow u"),
 ("08: q_acc unweighted", "extras/pcic_crosswalk/sql/pcic_crosswalk08_periods.sql", "sum(d.q_acc * b.n_days) / sum(b.n_days) AS q_acc", "avg(d.q_acc) AS q_acc"),
 ("export: monthly q_raw", "extras/pcic_crosswalk/sql/pcic_export.sql", "d.watershed_group_code, d.month, d.q_m3s", "d.watershed_group_code, d.month, d.q_raw"),
 ("export: weekly q_raw", "extras/pcic_crosswalk/sql/pcic_export.sql", "d.watershed_group_code, d.week, d.q_m3s", "d.watershed_group_code, d.week, d.q_raw"),
 ("export: month reversed", "extras/pcic_crosswalk/sql/pcic_export.sql", "d.watershed_group_code, d.month, d.q_m3s", "d.watershed_group_code, 13 - d.month, d.q_m3s"),
 ("export: week from month", "extras/pcic_crosswalk/sql/pcic_export.sql", "SELECT month, day, week FROM fwapg.pcic_day_bins", "SELECT month, day, month FROM fwapg.pcic_day_bins"),
 ("export: q_acc from q_local", "extras/pcic_crosswalk/sql/pcic_export.sql", "b.n_days, d.q_local, d.q_acc", "b.n_days, d.q_local, d.q_local"),
 ("load: stale daily kept", "load/pcic.sql", "DELETE FROM pcic.subbasin_daily t USING runs_in i\n  WHERE", "DELETE FROM pcic.subbasin_daily t USING runs_in i\n  WHERE false AND"),
 ("load: stale weekly kept", "load/pcic.sql", "DELETE FROM pcic.discharge_weekly t USING runs_in i\n  WHERE", "DELETE FROM pcic.discharge_weekly t USING runs_in i\n  WHERE false AND"),
]
for name, f, a, b in M:
    d = os.path.join(sp, "mut")
    shutil.rmtree(d, ignore_errors=True)
    for sub in ("extras/pcic_crosswalk", "load"):
        shutil.copytree(os.path.join(repo, sub), os.path.join(d, sub), ignore=shutil.ignore_patterns("data"))
    p = os.path.join(d, f); s = open(p).read()
    if s.count(a) < 1: print(f"NOT APPLIED  {name}"); continue
    open(p, "w").write(s.replace(a, b, 1) if "greatest(coalesce" not in a else s.replace(a, b, 1).replace("s.q_local * w.share, 0) AS q_m3s", "s.q_local * w.share) AS q_m3s"))
    r = subprocess.run(["bash", os.path.join(d, "extras/pcic_crosswalk/pcic_test.sh")], capture_output=True, text=True)
    fl = [l for l in r.stdout.splitlines() if l.startswith(("FAIL", "ABORTED"))]
    print(f"{'caught' if r.returncode and fl else 'MISSED'}  exit {r.returncode}  {name}: {fl[0][:90] if fl else ''}")
