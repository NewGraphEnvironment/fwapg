# PCIC routed flow on the FWA for any period: day bins, weights and the clamp

**Verified:** 2026-10-17 · **Issues:** NewGraphEnvironment/fwapg#6 (the first, monthly build), #9 (its publication), #25 (runs, daily climatology, weights, weekly flow), #23 (the `pcic` schema); cited by #28 (whether to route on the FWA instead) · **Produced by:** `extras/pcic_crosswalk/pcic_crosswalk.sh` run for PNWNAmet historical 1981-2010 with `WEEKLY=1` and for 1951-2012; `sql/qa_report_clamped.sql`; the probes and builds recorded in `planning/archive/2026-10-issue-25-pcic-crosswalk-run-parameters/`

## One daily climatology gives every period

PCIC's hydromosaic serves daily streamflow per outlet. The job keeps a daily climatology instead of
reducing it to months: `cdo ydaymean` over the run's years. In CDO 2.6.0 that gives 366 bins keyed by
calendar month and day, and Feb 29 is a bin of its own. It is not keyed by day of year, which would put
Mar 1 in a leap year with Feb 29 in other years. This was measured on a synthetic file whose value is
`month*100 + day`: every bin's mean equals its own date's value.

A bin's weight is the number of days of the period that fall on it (`n_days`). That is the number of
years, except for Feb 29, which counts only the leap years: 30 and 7 for 1981-2010. A month or a week is
then the `n_days`-weighted mean of its bins. For months this reproduces `cdo ymonmean` to 4e-8
relative, which is float precision. `outputtab` prints 4 decimals and shows a spurious 5e-5, so the
comparison needs `ncdump -p 9,17`.

A week is a fixed run of days in a 365-day year: `least((doy - 1) / 7 + 1, 52)`, with Feb 29 taking Feb
28's day of year. Week 1 is Jan 1-7, week 9 (Feb 26-Mar 4) also holds Feb 29, and week 52 is Dec 24-31
(8 days). Every year then has the same 52 weeks, and no week straddles two years.

## Flow on a segment is linear in the sub-basin flows until the clamp

Each FWA segment gets weights once, shared by every run:
- the sub-basin it drains to (`subid`);
- the share of that sub-basin's local runoff that passes it;
- the placed outlets directly above it (`upstream_subids`).

Then for any set of days

    q = greatest(sum(q_acc of upstream_subids) + q_local(subid) * share, 0)

with `q_acc` and `q_local` first averaged over the days. Everything before `greatest` is linear in the
daily sub-basin values. So averaging then routing equals routing then averaging, and one table of
sub-basin daily flow (`pcic.subbasin_daily`, 37,667 sub-basins × 366) with the weights
(`pcic.segment_weights`, 3,377,037 segments) gives any window exactly. A per-segment daily table would
hold 1.24 billion rows.

The clamp is not linear, so it is applied after averaging, per period, never per day. A window's flow
clamped per day and then averaged is a different, larger number.

## The crosswalk does not depend on the years

The crosswalk (which FWA segment each PCIC outlet sits on, and the flags) comes out byte-identical:
`md5 b1a710836df2cafea0ef514b7ed1c338` for both PNWNAmet periods and for the first 1951-2012 build
(#6, published in #9). It depends on which outlets have a series, and for PNWNAmet that set does not change with the years
(28 outlets of 48,716 have none). The export refuses a run whose crosswalk or weights differ from the
runs already in `pcic.runs`, so they can stay shared.

For CMIP6 this is not established. Three of the 28 outlets with no PNWNAmet series also return 422 for
CNRM-ESM2-1; the other 25 were not tried.

## Clamped flow: a weekly step adds none

Local runoff (an outlet's flow minus the flow of the placed outlets above it) can be negative over a
period, so a segment's flow before the clamp (`q_raw`) can be too. Some reaches lose water, and on a
rising hydrograph water is still in transit between outlets.

The concern before #25 was that a shorter step would turn that transit lag into many clamped segments
in the middle of the network, where the clamp hides water passing through. Measured on PNWNAmet
1981-2010:

| step | rows | clamped | % | mid-network rows | mid-network clamped | % |
|---|---|---|---|---|---|---|
| month | 40,524,444 | 396,489 | 0.978 | 3,211,404 | 1,579 | 0.049 |
| week | 175,605,924 | 1,715,490 | 0.977 | 13,916,084 | 6,742 | 0.048 |

Mid-network rows are on segments that have placed outlets above them and are not an outlet's own
segment: 267,617 of 3,377,037.

- **Seasons:** clamping is a freshet effect.
  - Months: Apr 3.73%, May 4.12% and Jun 2.47% of segments. Mid-network: 404, 774 and 390.
  - Weeks: 16-22 (Apr 16 to Jun 3) carry 3.8-4.3%. Mid-network: 620-805, the worst being week 22, May 28-Jun 3.
  - Nov-Feb: under 0.01%, and none mid-network.
- **Steps:** the overall share does not move with the step, and the worst week is 4% above the worst month on mid-network segments (805 against 774). The clamp is a property of where outlets sit, and a month-long mean already contains it.
- **Size:** most clamped rows are not float noise around zero. 81% are more than 1 L/s below zero, at either step, and so are 1,577 of the 1,579 monthly mid-network rows.

A daily step is not measured. Weekly flow is the shortest step published, and the weights give a daily
or any other window on demand.

## Output size and build time

Measured for 1981-2010 with `WEEKLY=1` on a local Docker PostgreSQL 17.5 (128 GB machine):

| table | rows | `.csv.gz` |
|---|---|---|
| `pcic.segment_weights` | 3,377,037 | 37.8 MB |
| `pcic.fwa_crosswalk` | 48,716 | 1.7 MB |
| `pcic.subbasin_daily`, per run | 13,786,122 | 280.1 MB |
| `pcic.discharge_monthly`, per run | 40,524,444 | 232.4 MB |
| `pcic.discharge_weekly`, per run | 175,605,924 | 987.8 MB |

The run took 2 h 53 min:
- network paging: 4 min;
- fetching and reducing the series: 27 min;
- the crosswalk, weights and both flow tables: 50 min;
- QA: 4 min;
- the export swap: 79 min, almost all of it the weekly rows going into a primary-keyed table;
- the `.csv.gz` files: 10 min.

The 1951-2012 run, monthly only, took 1 h 15 min:
- network paging: 4 min;
- fetching: 19 min;
- the crosswalk, weights and monthly flow: 32 min;
- QA, swap and files: 21 min.

So `WEEKLY=1` costs about 1.5 h, mostly in the swap.

## The rebuild reproduces the first build exactly

The 1951-2012 run, rebuilt through the daily climatology and the weights, reproduces the first build's
monthly table row for row:
- 40,524,444 rows on 3,377,037 segments;
- `sum(round(q_m3s::numeric, 6))` = 178035348.248310;
- no row differs, at any precision.

Monthly means derived from the daily cache, with `n_days` as weights, match the first build's
`cdo ymonmean` output at all 584,256 (subid, month) pairs: the largest difference is 2.5e-11 m³/s,
1.0e-14 relative.

The gauge check repeats the first build's numbers (494 of 538 gauges within 10% of PCIC). PCIC's flow
over observed has a median of 0.949 over 1951-2012 and 0.988 over 1981-2010, at 543 and 435 gauges.

`upstream_subids` is aggregated without an order, so its element order can differ between builds.
940 of the 87,444 multi-element arrays are not sorted, and the weights `.csv.gz` came out 26 bytes
smaller in the second build. Compare the arrays as sets. The fingerprint `pcic.runs` holds (rows and the
sum of `share`) agreed to 9 decimals.

## CMIP6 runs

hydromosaic serves 9 CMIP6 GCMs × 2 scenarios on the same outlets:
- the model is named exactly as in `GET /outlets/<subid>/timeseries` (e.g. `CNRM-ESM2-1`);
- the scenario is `historical, ssp245` or `historical, ssp585`, comma and space included;
- every series is gregorian, 55,152 days (1950-2100), with 37 Feb 29s.

A 50-outlet request took 34 s, against 11 s for PNWNAmet, which puts a full run's fetch at roughly
1.5 h. The job takes them as `MODEL` and `SCENARIO`. None has been built.
