# /// script
# requires-python = ">=3.11"
# dependencies = ["netCDF4>=1.6", "numpy>=1.26", "pyarrow>=15"]
# ///
"""Per-year sub-basin days for pcic_crosswalk.sh (DAYS=1). See README.md.

  rows <year> <nc...>
      Print subid,month,day,q_m3s for every day of <year> and every outlet in the
      kept hydromosaic NetCDF files, as pcic_crosswalk.sh copies them into
      fwapg.pcic_outlet_year. Refuses a calendar with no real dates, a day of the
      year missing or repeated, a fill or non-finite value, and an outlet in two
      files.

  parquet <year> <out> <crosswalk md5> <commit>
      Read subid,month,day,q_local,q_acc for one year from stdin (CSV, no header)
      and write <out>: subid int32, date date32, q_local float32, q_acc float32,
      sorted by subid and date, zstd, 1,000 sub-basins per row group, with the md5
      of the crosswalk the days were routed on and the fwapg commit that built them
      in the file's metadata (fwapg.crosswalk_md5, fwapg.commit). Refuses a
      sub-basin without every day of the year, a NULL and a non-finite value.

  fingerprint <file...>
      Print each file's pcic.series line: year,rows,subbasins,q_local_sum,
      q_acc_sum,bytes,crosswalk_md5,commit. Refuses a file named for another year
      than it holds, and one without the metadata. A sum is sum(floor(double(v) * 1000 + 0.5)) over the stored
      float32 values v, as a 64-bit integer: double(v) * 1000 is exact for a
      float32, so every reader reproduces it bit for bit.

  means <year1> <year2> <file...>
      Print subid,month,day,q_local,q_acc,abs_local,abs_acc,n: per sub-basin and
      calendar day, the mean over the years <year1>-<year2> of the files given and
      the mean of each value's magnitude (sql/qa_days.sql's tolerance), in float64
      from the stored float32 values, and the number of years on that day.

  months <file>
      Print year,subid,month,q_local,q_acc: the file's monthly means, in float64
      from the stored float32 values.

  meta <file>
      Print the file's crosswalk_md5,commit (empty where it has none).

  dump <file>
      Print subid,date,q_local,q_acc: the file's rows, the float32 values written
      exactly (pcic_test.sh).
"""

import calendar
import csv
import io
import os
import re
import sys

import numpy as np

SUBBASINS_PER_GROUP = 1000


def die(msg):
    sys.exit(f"pcic_days.py: {msg}")


def year_days(year):
    """Every date of the year, as datetime64[D]."""
    return np.arange(np.datetime64(f"{year}-01-01"), np.datetime64(f"{year + 1}-01-01"), dtype="datetime64[D]")


def rows(year, files):
    import netCDF4

    days = year_days(year)
    seen = set()
    out = sys.stdout
    for f in files:
        with netCDF4.Dataset(f) as ds:
            t = ds.variables["time"]
            cal = getattr(t, "calendar", "standard").lower()
            if cal not in ("standard", "gregorian", "proleptic_gregorian"):
                die(f"{f}: calendar {cal} has no real dates")
            dates = netCDF4.num2date(t[:], t.units, cal, only_use_cftime_datetimes=False, only_use_python_datetimes=True)
            d = np.array([np.datetime64(x.date(), "D") for x in dates])
            idx = np.flatnonzero((d >= days[0]) & (d <= days[-1]))
            if len(idx) != len(days) or not np.array_equal(d[idx], days):
                die(f"{f}: {year} has {len(idx)} days, not each of its {len(days)} once and in order")
            names = netCDF4.chartostring(ds.variables["basin_name"][:]) if ds.variables["basin_name"].dtype == "S1" else ds.variables["basin_name"][:]
            subids = [int(str(x)) for x in np.asarray(names).ravel()]
            dup = seen.intersection(subids)
            if dup or len(set(subids)) != len(subids):
                die(f"{f}: outlet {sorted(dup)[:5] if dup else 'repeated'} in more than one place")
            seen.update(subids)
            v = ds.variables["streamflow"]
            if v.dimensions != ("time", "outlet"):
                die(f"{f}: streamflow is {v.dimensions}, not (time, outlet)")
            q = v[idx[0]:idx[-1] + 1, :]
            if np.ma.is_masked(q) or not np.all(np.isfinite(np.ma.getdata(q))):
                die(f"{f}: a fill or non-finite value in {year}")
            q = np.ma.getdata(q).astype(np.float64)
            md = [(int(str(x)[5:7]), int(str(x)[8:10])) for x in days]
            buf = io.StringIO()
            for j, s in enumerate(subids):
                col = q[:, j]
                buf.writelines(f"{s},{m},{dd},{x!r}\n" for (m, dd), x in zip(md, col.tolist()))
            out.write(buf.getvalue())


META = (b"fwapg.crosswalk_md5", b"fwapg.commit")


def parquet(year, path, crosswalk_md5, commit):
    if not re.fullmatch(r"[0-9a-f]{32}", crosswalk_md5):
        die(f"not an md5: {crosswalk_md5}")
    if not re.fullmatch(r"[0-9a-f]{7,40}", commit):
        die(f"not a commit: {commit}")
    import pyarrow as pa
    import pyarrow.csv as pacsv
    import pyarrow.parquet as pq

    t = pacsv.read_csv(
        sys.stdin.buffer,
        read_options=pacsv.ReadOptions(column_names=["subid", "month", "day", "q_local", "q_acc"]),
        convert_options=pacsv.ConvertOptions(
            column_types={"subid": pa.int32(), "month": pa.int32(), "day": pa.int32(), "q_local": pa.float64(), "q_acc": pa.float64()},
            strings_can_be_null=False,
        ),
    )
    ndays = 366 if calendar.isleap(year) else 365
    if t.num_rows == 0:
        die(f"no rows for {year}")
    cols = {}
    for c in ("subid", "month", "day", "q_local", "q_acc"):
        if t[c].null_count:
            die(f"{c} is NULL in {t[c].null_count} rows")
        cols[c] = t[c].to_numpy()
    month = cols["month"]
    day = cols["day"]
    date = (np.datetime64(f"{year}-01", "M") + (month - 1)).astype("datetime64[D]") + (day - 1)
    bad = (month < 1) | (month > 12) | (day < 1) | (date.astype("datetime64[M]") != np.datetime64(f"{year}-01", "M") + (month - 1))
    if bad.any():
        die(f"{int(bad.sum())} rows are not days of {year}")
    order = np.lexsort((date, cols["subid"]))
    subid = cols["subid"][order]
    date = date[order]
    n = len(subid)
    nsub = len(np.unique(subid))
    if n != nsub * ndays or np.any((subid[1:] == subid[:-1]) & (date[1:] == date[:-1])):
        die(f"{n} rows for {nsub} sub-basins: not every day of {year} once for each")
    q = {}
    for c in ("q_local", "q_acc"):
        v = cols[c][order].astype(np.float32)
        if not np.all(np.isfinite(v)):
            die(f"{c} is not finite (or not a float32) in {int((~np.isfinite(v)).sum())} rows")
        q[c] = v
    table = pa.table({
        "subid": pa.array(subid, pa.int32()),
        "date": pa.array(date, pa.date32()),
        "q_local": pa.array(q["q_local"], pa.float32()),
        "q_acc": pa.array(q["q_acc"], pa.float32()),
    }).replace_schema_metadata({META[0]: crosswalk_md5.encode(), META[1]: commit.encode()})
    tmp = path + ".tmp"
    pq.write_table(table, tmp, compression="zstd", row_group_size=SUBBASINS_PER_GROUP * ndays)
    os.replace(tmp, path)


def read(path):
    import pyarrow.parquet as pq

    t = pq.read_table(path)
    if t.schema.names != ["subid", "date", "q_local", "q_acc"]:
        die(f"{path}: columns {t.schema.names}")
    for c in t.schema.names:
        if t[c].null_count:
            die(f"{path}: {c} is NULL in {t[c].null_count} rows")
    date = t["date"].to_numpy().astype("datetime64[D]")
    years = np.unique(date.astype("datetime64[Y]").astype(int) + 1970)
    if len(years) != 1:
        die(f"{path}: dates of {len(years)} years")
    q = {c: t[c].to_numpy().astype(np.float32).astype(np.float64) for c in ("q_local", "q_acc")}
    for c, v in q.items():
        if not np.all(np.isfinite(v)):
            die(f"{path}: {c} is not finite")
    return int(years[0]), t["subid"].to_numpy(), date, q


def meta(path):
    import pyarrow.parquet as pq

    m = pq.read_schema(path).metadata or {}
    return m.get(META[0], b"").decode(), m.get(META[1], b"").decode()


def fp_sum(v):
    return int(np.floor(v * 1000 + 0.5).astype(np.int64).sum())


def fingerprint(files):
    w = csv.writer(sys.stdout, lineterminator="\n")
    for f in files:
        year, subid, _, q = read(f)
        named = re.search(r"\.([0-9]{4})\.parquet$", f)
        if named and int(named.group(1)) != year:
            die(f"{f} holds the days of {year}")
        md5, commit = meta(f)
        if not md5 or not commit:
            die(f"{f} does not name the crosswalk and commit it was built from")
        w.writerow([year, len(subid), len(np.unique(subid)), fp_sum(q["q_local"]), fp_sum(q["q_acc"]), os.path.getsize(f), md5, commit])


def month_day(date):
    m = date.astype("datetime64[M]")
    return (m.astype(int) % 12 + 1), (date - m.astype("datetime64[D]")).astype(int) + 1


def means(y1, y2, files):
    # sums per sub-basin and calendar day (366 bins, a leap year's), file by file
    subids = sums = None
    for f in files:
        year, subid, date, q = read(f)
        if not y1 <= year <= y2:
            continue
        month, day = month_day(date)
        # the calendar day's place in a leap year, 0-365
        cal = ((np.datetime64("2000-01", "M") + (month - 1)).astype("datetime64[D]") + (day - 1) - np.datetime64("2000-01-01")).astype(np.int64)
        if subids is None:
            subids = np.unique(subid)
            sums = np.zeros((5, len(subids) * 366))
        s = np.searchsorted(subids, subid)
        if np.any(s >= len(subids)) or np.any(subids[np.minimum(s, len(subids) - 1)] != subid) or len(np.unique(subid)) != len(subids):
            die(f"{f}: not the sub-basins of the other files")
        k = s * 366 + cal
        for i, v in enumerate((q["q_local"], q["q_acc"], np.abs(q["q_local"]), np.abs(q["q_acc"]), np.ones(len(k)))):
            sums[i] += np.bincount(k, v, minlength=len(subids) * 366)
    if subids is None:
        die(f"no file of {y1}-{y2}")
    n = sums[4]
    keep = np.flatnonzero(n > 0)
    m = [sums[i][keep] / n[keep] for i in range(4)]
    cal = np.datetime64("2000-01-01") + (keep % 366)
    mo, dd = month_day(cal)
    sid = subids[keep // 366]
    buf = io.StringIO()
    for row in zip(sid.tolist(), mo.tolist(), dd.tolist(), *(x.tolist() for x in m), n[keep].astype(np.int64).tolist()):
        buf.write("%d,%d,%d,%r,%r,%r,%r,%d\n" % row)
    sys.stdout.write(buf.getvalue())


def months(path):
    year, subid, date, q = read(path)
    month, _ = month_day(date)
    key = subid.astype(np.int64) * 100 + month
    u, inv, n = np.unique(key, return_inverse=True, return_counts=True)
    ql = np.bincount(inv, q["q_local"]) / n
    qa = np.bincount(inv, q["q_acc"]) / n
    buf = io.StringIO()
    for k, a, b in zip(u.tolist(), ql.tolist(), qa.tolist()):
        buf.write("%d,%d,%d,%r,%r\n" % (year, k // 100, k % 100, a, b))
    sys.stdout.write(buf.getvalue())


def dump(path):
    _, subid, date, q = read(path)
    buf = io.StringIO()
    for row in zip(subid.tolist(), date.astype(str).tolist(), q["q_local"].tolist(), q["q_acc"].tolist()):
        buf.write("%d,%s,%r,%r\n" % row)
    sys.stdout.write(buf.getvalue())


def year_arg(x):
    if not re.fullmatch(r"[0-9]{4}", x):
        die(f"not a year: {x}")
    return int(x)


def main(argv):
    if len(argv) >= 3 and argv[0] == "rows":
        rows(year_arg(argv[1]), argv[2:])
    elif len(argv) == 5 and argv[0] == "parquet":
        parquet(year_arg(argv[1]), argv[2], argv[3], argv[4])
    elif len(argv) >= 2 and argv[0] == "fingerprint":
        fingerprint(argv[1:])
    elif len(argv) >= 4 and argv[0] == "means":
        means(year_arg(argv[1]), year_arg(argv[2]), argv[3:])
    elif len(argv) == 2 and argv[0] == "months":
        months(argv[1])
    elif len(argv) == 2 and argv[0] == "meta":
        print(",".join(meta(argv[1])))
    elif len(argv) == 2 and argv[0] == "dump":
        dump(argv[1])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
