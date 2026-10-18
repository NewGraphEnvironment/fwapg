# Review: pcic_test.sh, round 3

Reviewed 2026-10-18 UTC against the working tree (staged diff `diff_r3.patch`). Every verdict below
marked "measured" comes from a mutation run on a copy of `extras/pcic_crosswalk` + `load` (scratchpad
`mutate_rev3.py`, `mutate_rev3b.py`, `mutate_rev3c.py`: 38 mutations, about 18 s each, run one at a
time; scratch databases confirmed dropped afterwards). Earlier sweeps are cited as r2 (`mutate_r2.py`,
35) and r3 (`mutate_r3.py`, 8). Baseline: all pass, 18 s.

## The mechanism

R1 (every upstream sub-basin a headwater) and R2 (one UNION arm of three, one `\copy` of five) share one
cause. **Each guard, key and fingerprint is tested with one hand-built input chosen to trip it as a
whole. Nothing in the fixture differs from a passing input in exactly the one thing a given component
looks at.** So the test proves that each guard fires. It does not prove that each component of its
condition, or each column of its key, does any work. It shows up in two forms:

1. **An input that violates every component at once.** The truncated file (`head -20`) changes rows,
   keys and sum together. The "Local" run has `crosswalk_md5 = 'another'` and NULL weights. Any one
   component of those conditions can be removed and the refusal still fires.
2. **A second run that is a copy of the first wherever it was not deliberately changed.** The
   1951-2012 run has the same `subbasin_daily` as 1981-2010 (line 225 doubles only the monthly flow).
   Only 1981-2010 has weekly rows. The window checks run while only one run is exported. So a key or
   filter that confuses runs gets caught only where it shares a template with something both runs hold
   differently (monthly flow).

## Findings

- **[severity: fragile]** load/pcic_run.sql:49, pcic_test.sh:286-289. Nothing tests the sum of flow in
  the run-file fingerprint. Mutation A, `(got_rows, got_keys) IS DISTINCT FROM (want_rows, want_keys)`,
  passes the whole suite (exit 0). The only fingerprint test is the truncated file, which also changes
  rows and keys. The sum is the only component that reads values. Without it, a file with the right
  rows and keys but other values loads silently. That is exactly the case of a published run file
  replaced by a rerun's while `pcic.runs.csv.gz` stays stale. The header (pcic_run.sql:7-8) claims
  "rows, keys and the sum of flow". Rows alone (B2) and keys alone (B) are also untested, but a change
  to those without a change to the sum is contrived. Fix: refuse a copy of `$m` with one `q_m3s` value
  edited and rows and keys unchanged.

- **[severity: fragile]** load/pcic.sql:49, pcic_test.sh:315-316. The load's "a run here on another
  crosswalk or weights, not published" refusal is tested only with a row that differs in all three
  components. Mutation E (drop `crosswalk_md5` from the tuple) and mutation E2 (drop both weights
  components) each pass with exit 0. The test itself treats a crosswalk-only difference as real: line
  231 refuses an export on a `demoted` flag with the weights unchanged. The weights-only case is the
  "reloaded FWA" case in pcic_export.sql:8. With either half missing, a local unpublished run built on
  another crosswalk, or on other weights, stays listed while `pcic.fwa_crosswalk` and
  `pcic.segment_weights` are replaced under it. That is the silent outcome load/pcic.sql:8-10 says the
  check exists to stop. Fix: two Local rows, one with the published md5 and other weights, one with
  another md5 and the published weights, each refused.

- **[severity: fragile]** load/pcic.sql:84-85, pcic_test.sh:257-260 and 332-336. The stale weekly
  DELETE's run key is untested. Mutation G (`WHERE t.model = i.model`) passes with exit 0. Only
  1981-2010 has weekly rows, so a key that matches on model alone deletes nothing extra. The daily and
  monthly keys are caught (G2, Q11) only because both runs hold rows in those tables. Once two runs of
  one model have weekly flow loaded, a reload where one run's weekly fingerprint changed would delete
  the other run's valid weekly rows. `pcic.runs` would still list `weekly_rows` for that run, and
  nothing checks after a load, so the loss is silent. Fix: give 1951-2012 weekly rows (export it with
  weekly flow and load the file) before the reload checks, and expect them kept.

- **[severity: fragile]** README.md:283, pcic_test.sh:219-223 and 225. The window query's run filter
  is untested. Mutation H (drop `(model, scenario, period) = (...)`) passes with exit 0. Two causes:
  the window checks run before the second run is exported, and the second run's `subbasin_daily` is
  identical to the first's anyway (only `pcic_discharge_monthly` is doubled). `load.sh` loads two runs
  (README.md:300), so a query without the filter would silently average 1951-2012 and 1981-2010. Fix:
  change `fwapg.pcic_subbasins_daily` before the second export, and run the window checks after it.

- **[severity: fragile]** load/pcic.sql:92, pcic_test.sh:315-317 and 329-336. Nothing tests that a load
  keeps a compatible local run in `pcic.runs`. Mutation F (`DELETE FROM pcic.runs;`, every row) passes
  with exit 0. Every successful reload in the test runs with only published runs present. A local
  unpublished run on the same crosswalk and weights passes the "other" check and then loses its
  `pcic.runs` row, while its rows stay behind, unlisted and unchecked. The next export or load refuses
  them as orphans, so the failure surfaces later and at a distance. Fix: before one successful reload,
  insert a Local run row carrying the published md5 and weights, and expect it still listed.

- **[severity: fragile, low]** The count components of four conditions are never exercised alone:
  - pcic_export.sql:33 `weights_rows` (mutation D)
  - load/pcic.sql:40 `weights_rows IS DISTINCT FROM w_rows` (mutation C)
  - load/pcic.sql:73/81/89 `*_rows`/`*_segments` in the stale DELETEs (mutation J, monthly measured)

  All of these pass with exit 0. The test's weights edits change only `share`. That matters because
  zero-valued rows are real: 07_segments.sql:99-101 sets `share` to 0 (the `greatest(..., 0)` and the
  `ELSE 0`), and the clamp sets `q_m3s` to 0. A weights set or a run that differs only in zero-valued
  rows has an unchanged sum, and only the count arm catches it. Fix: one weights edit that adds or
  drops a share-0 row with the sum unchanged.

The header and README claims are backed. The header's "every refusal ... but pcic_run.sql's table-name
check" holds at refusal level: each RAISE and each HEADER MATCH is reached and asserted by its message.
The findings above concern components inside those refusals. The README's "under 30 seconds" matches
the measured 18 s.

## Enumeration

Verdict key: **caught**, with the check that fails. **MISSED**, a finding above. **gap (not
reported)**, the mutant passes but ships nothing wrong. **equivalent**, the mutant cannot change the
output. **accepted**, a tradeoff listed in the brief.

### sql/pcic_crosswalk01_days.sql

| # | element | mutation | verdict |
|---|---|---|---|
| 1 | calendar of 366 days (from 2000) | r2 "Feb 29 not folded" | caught (setup abort; accepted) and the "366 calendar days" check |
| 2 | `generate_series(make_date(:y1,1,1), make_date(:y2,12,31))` | Q10, Dec 30 | caught: "a period with no leap year gives Feb 29 no days" |
| 3 | `coalesce(d.n_days, 0)` | r2 | caught |
| 4 | week formula on 2001 (non-leap doy) | r2, 2000 | caught |
| 5 | `least(..., 52)` | r2, 53 | caught |
| 6 | Feb 29 onto Feb 28 | r2 | caught (abort, accepted) |
| 7 | LEFT JOIN on month and day | reasoned: dropping `day` multiplies n_days | caught by "every other day on 30" |
| 8 | primary key | loud on duplicates | n/a |

### sql/pcic_crosswalk08_periods.sql

| # | element | mutation | verdict |
|---|---|---|---|
| 9 | outlet weighted mean | r2, `avg()` | caught: outlet monthly check (weekly shares the template) |
| 10 | outlet join on day bins | Q15, `AND b.n_days > 0` | equivalent (n_days 0 adds nothing); other changes caught by #9 |
| 11 | `GROUP BY ..., b.:step` | a week-only change errors | loud |
| 12 | sub-basin q_local weighted | r2 | caught |
| 13 | sub-basin q_acc weighted | r2 | caught |
| 14 | sub-basin join | reasoned: dropping `day` gives the unweighted mean | caught as #12 |

### sql/pcic_crosswalk09_discharge.sql

| # | element | mutation | verdict |
|---|---|---|---|
| 15 | q_raw and q_m3s columns | value checks compare both | caught |
| 16 | `m.subid = w.subid` | value checks | caught |
| 17 | `u.subid = ANY(upstream_subids)` | r2 | caught |
| 18 | `AND u.:step = m.:step` | Q8 | caught: segment monthly |
| 19 | `sum(u.q_acc)`, not q_local | r2 | caught |
| 20 | `coalesce(..., 0)` | Q9 | caught: segment monthly |
| 21 | `q_local * share` | shares 0.25 / 0.4 / 0.5 in the fixture | caught by value checks |
| 22 | clamp after averaging | r2 (no clamp); per-day clamp distinguishable | caught |
| 23 | `round(, 5)` | 1e-12 compare | caught |
| 24 | `WHERE watershed_group_code = :'wsg'` | L | gap (not reported): values identical; ON CONFLICT DO NOTHING under xargs (pcic_crosswalk.sh:246) |
| 25 | ON CONFLICT DO NOTHING | removal raises on conflict | loud |

### sql/pcic_export.sql

| # | element | mutation | verdict |
|---|---|---|---|
| 26 | run.crosswalk_md5 formula | Q13 | caught: "load the shared tables" |
| 27 | run.weights_share_sum | P | caught |
| 28 | other: whole guard | r2 | caught |
| 29 | other: crosswalk component | crosswalk-only edit, line 231 | caught |
| 30 | other: weights_share_sum component | P | caught |
| 31 | other: weights_rows component | D | **MISSED** (low finding) |
| 32 | other: self-exemption (line 32) | stricter only | accepted |
| 33-35 | orphan UNION arms: daily, monthly, weekly | r3 | caught, each |
| 36 | orphan: self-exemption | stricter only | accepted |
| 37 | TRUNCATE + INSERT crosswalk, weights, day_bins | r2, "week from month" | caught by same() |
| 38 | DELETE daily, run key | Q1 | caught: load daily 1981-2010 |
| 39 | INSERT daily columns, n_days | r2, q_acc from q_local | caught by same() |
| 40 | DELETE monthly, run key | Q2 | caught |
| 41 | INSERT monthly columns | r2, q_raw and month reversed | caught |
| 42 | DELETE weekly, present and keyed | r2 (removed), Q3 (model only) | caught |
| 43 | `\if :weekly`, both branches | weekly 1 and 0 both run | caught (r2) |
| 44 | INSERT weekly columns | r2, weekly q_raw | caught |
| 45 | DELETE pcic.runs, run key | Q4 | caught |
| 46 | runs d / m / k lateral run key | Q5 (d); m and k reasoned by the same refusal and the `'0\|'` check | caught |
| 47 | k `nullif(count(*), 0)` | Q6 | caught |
| 48 | k `nullif(count(DISTINCT ...), 0)` | I | gap (not reported): only load/pcic.sql:89 reads weekly_segments, comparing two export-written values |
| 49 | q_sum column and rounding | R3 (the counterpart in pcic_run) | caught |

### load/pcic.sql

| # | element | mutation | verdict |
|---|---|---|---|
| 50-53 | four `\copy ... header match` | r3 | caught, each |
| 54 | "lists no runs" | r2 | caught |
| 55 | md5 check | r2 | caught |
| 56 | md5 check, any run vs every run | N | gap (not reported): export's guard cannot write a mixed runs file, and pcic_run.sql:53 refuses each odd run's file loudly |
| 57 | weights check, share arm | C2 | caught |
| 58 | weights check, rows arm | C | **MISSED** (low finding) |
| 59 | weights check, any run vs every run | O | gap (not reported): needs a mixed runs file, which export's guard prevents |
| 60 | 366 days | r2 | caught |
| 61 | other: whole guard | r2 | caught |
| 62 | other: crosswalk component | E | **MISSED** (finding) |
| 63 | other: weights components | E2 | **MISSED** (finding) |
| 64 | other: published exemption (~:48) | stricter only | accepted |
| 65-67 | orphan UNION arms | r3 | caught, each |
| 68 | orphan: runs_in exemption | stricter only | accepted |
| 69 | stale daily DELETE: key / q_sum / rows and keys | G2 caught / r2 caught / J analogue | caught, caught, **MISSED** (low) |
| 70 | stale monthly DELETE: key / q_sum / rows and segments | Q11 caught / r2 caught / J | caught, caught, **MISSED** (low) |
| 71 | stale weekly DELETE: key / q_sum / rows and segments | G / r2 caught / J analogue | **MISSED** (finding), caught, **MISSED** (low) |
| 72 | stale DELETEs: crosswalk_md5 | stricter only | accepted |
| 73 | DELETE pcic.runs, run key | F | **MISSED** (finding) |
| 74 | INSERT runs, crosswalk, weights, day_bins | md5 compare between the two databases | caught |

### load/pcic_run.sql

| # | element | mutation | verdict |
|---|---|---|---|
| 75 | `\copy ... header match` | r2 | caught |
| 76 | table name | unreachable | accepted |
| 77 | `n != 1` | r2 | caught |
| 78 | fingerprint lookup, run key | K | caught: load monthly 1951-2012 |
| 79 | "not in pcic.runs" | r2 | caught |
| 80 | fingerprint: sum | A | **MISSED** (finding) |
| 81 | fingerprint: keys | B | **MISSED** (low, under finding 1) |
| 82 | fingerprint: rows | B2 | **MISSED** (low, under finding 1) |
| 83 | prefix and column mapping | Q12, R3 | caught |
| 84 | crosswalk check | r2 | caught |
| 85 | DELETE, run key | Q7 | caught: rows loaded |
| 86 | INSERT | md5 compare | caught |

### README window query

| # | element | mutation | verdict |
|---|---|---|---|
| 87 | run filter | H | **MISSED** (finding) |
| 88 | Feb 29 onto Feb 28 | Q14 | caught: winter window |
| 89 | window dates | winter replacement check | caught |
| 90 | q_local weighted | r2 | caught |
| 91 | q_acc weighted | R1 | caught: winter window |
| 92 | upstream `sum(u.q_acc)` | r2 | caught |
| 93 | coalesce | R2 | caught |
| 94 | clamp | r2 | caught |
| 95 | `watershed_group_code = 'BULK'` | M | gap (not reported): returns other groups' rows, with correct values |

**Count.** 95 elements:

| verdict | count |
|---|---|
| caught (or loud) | 68 |
| accepted | 9 |
| gap, not reported | 6 |
| equivalent | 1 |
| MISSED, reported as findings | 6 groups |

The 6 reported groups:

| group | elements |
|---|---|
| fingerprint sum | 80 |
| load "other" check | 62 and 63 |
| stale weekly key | 71 (key) |
| window run filter | 87 |
| pcic.runs DELETE | 73 |
| count arms (low) | 31, 58, 69-71 (rows/keys), 81, 82 |
