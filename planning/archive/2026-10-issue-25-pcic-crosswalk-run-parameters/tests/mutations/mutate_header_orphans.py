import os, shutil, subprocess, sys
repo, sp = sys.argv[1], sys.argv[2]
M = [
 ("load: runs plain HEADER", "load/pcic.sql", "pcic.runs.csv.gz | gunzip' with (format csv, header match)", "pcic.runs.csv.gz | gunzip' with (format csv, header)"),
 ("load: crosswalk plain HEADER", "load/pcic.sql", "pcic.fwa_crosswalk.csv.gz | gunzip' with (format csv, header match)", "pcic.fwa_crosswalk.csv.gz | gunzip' with (format csv, header)"),
 ("load: weights plain HEADER", "load/pcic.sql", "pcic.segment_weights.csv.gz | gunzip' with (format csv, header match)", "pcic.segment_weights.csv.gz | gunzip' with (format csv, header)"),
 ("load: day_bins plain HEADER", "load/pcic.sql", "pcic.day_bins.csv.gz | gunzip' with (format csv, header match)", "pcic.day_bins.csv.gz | gunzip' with (format csv, header)"),
 ("export: orphan arm daily dropped", "extras/pcic_crosswalk/sql/pcic_export.sql", "    SELECT DISTINCT model, scenario, period FROM pcic.subbasin_daily\n    UNION", "    SELECT DISTINCT model, scenario, period FROM pcic.discharge_monthly\n    UNION"),
 ("export: orphan arm weekly dropped", "extras/pcic_crosswalk/sql/pcic_export.sql", "    UNION SELECT DISTINCT model, scenario, period FROM pcic.discharge_weekly\n  ) o", "  ) o"),
 ("load: orphan arm daily dropped", "load/pcic.sql", "      SELECT DISTINCT model, scenario, period FROM pcic.subbasin_daily\n      UNION", "      SELECT DISTINCT model, scenario, period FROM pcic.discharge_weekly\n      UNION"),
 ("load: orphan arm monthly dropped", "load/pcic.sql", "      UNION SELECT DISTINCT model, scenario, period FROM pcic.discharge_monthly\n", ""),

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
