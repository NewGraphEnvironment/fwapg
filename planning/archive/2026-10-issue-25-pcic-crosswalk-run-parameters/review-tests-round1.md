# Review: extras/pcic_crosswalk/pcic_test.sh, round 1

Ran it from a copy. It passes under both `/bin/bash` 3.2.57 and Homebrew bash, against the PostgreSQL 17 server, in 12 s by `date -u`. The EXIT trap keeps a failing status under bash 3.2 (checked). I ran 11 more mutations, each on a copy (`scratchpad/mut2.py`). 9 of them pass the test, with exit 0 and no FAIL line.

## Findings

- **[bug] pcic_test.sh:97-109 (fixture)**: the only upstream sub-basins are 1 and 3, and both are headwaters: `q_acc = q_local` for every subid but 2, and 2 is upstream of nothing. So the core term `sum(q_acc of upstream_subids)` can never be told apart from `sum(q_local ...)`. Measured, both pass:
  - `sql/pcic_crosswalk09_discharge.sql` `SELECT sum(u.q_acc)` -> `sum(u.q_local)`: MISSED, exit 0
  - README window query `SELECT sum(u.q_acc) FROM window_flow u` -> `sum(u.q_local) ...`: MISSED, exit 0

  On real data most upstream outlets are not headwaters, so this mistake would put wrong flow on most non-headwater segments. Fix: add a sub-basin whose outlet takes sub-basin 2 (for example 4, with 2 draining to it, `q_acc(4)` the sum over 1-4), and a segment in sub-basin 4 with `upstream_subids = '{2}'`. The routed reference (lines 120-131) already takes `q_acc` from the table, so it needs no change.

- **[bug] pcic_test.sh:179-249 (export)**: no check compares what `sql/pcic_export.sql` writes into `pcic.*` with its source in `fwapg.*`. Line 248 compares the export with the load, two copies of the same output, and the runs fingerprints are computed from the `pcic` tables themselves, so they agree with whatever was written. Measured, all pass:
  - export monthly `d.q_m3s` -> `d.q_raw` (unclamped, negative flow published): MISSED
  - export weekly `d.q_m3s` -> `d.q_raw`: MISSED
  - export monthly `d.month` -> `13 - d.month`: MISSED
  - export `pcic.day_bins` `week` -> `month`: MISSED
  - export `pcic.subbasin_daily` `q_acc` <- `d.q_local`: MISSED (the window query reads `q_acc` only for subids 1 and 3, where the two are equal; see the finding above)

  The header and the README say the test covers "its export into the pcic schema". As written it covers the guards and the row counts, not the values. Fix: after the first export, compare `pcic.discharge_monthly`/`_weekly` (period 1981-2010) with `fwapg.pcic_discharge_*` on (lfid, step, q_m3s), `pcic.day_bins` with `fwapg.pcic_day_bins` (month, day, week), and `pcic.subbasin_daily` with `fwapg.pcic_subbasins_daily` joined to the bins' `n_days`. Use EXCEPT both ways, or a count of joined matches.

- **[fragile] pcic_test.sh:286-290**: the check is labelled "only the rows unlike the published run are dropped: period, daily, monthly, weekly", but it makes only the monthly fingerprint differ. The daily and weekly DELETE branches of `load/pcic.sql` are tested only where they must keep rows, never where they must drop them. Measured: `load/pcic.sql` daily DELETE `WHERE` -> `WHERE false AND` is MISSED, and the same on the weekly DELETE is MISSED. Fix: also bump `daily_q_sum` (of the other period, say) and `weekly_q_sum`, then expect those rows dropped too.

- **[fragile] pcic_test.sh:248**: `check` gets two command substitutions. If both psql calls error, both sides are empty and the check reports `ok` (command substitution does not trigger `set -e`). The code under test cannot easily make both fail, so this is low risk. A non-empty guard, for example comparing `count(*)` along with the md5, would close it.

## Not findings (checked)

- The header's list of refusals matches the code: both in the export, all six in `load/pcic.sql`, and all in `load/pcic_run.sql` except the table-name check, as stated.
- The `checks` row-count guard catches a psql failure inside `< <(...)`, because a missing line counts as a failure.
- `local_load` fails loudly if `load/pcic.sql`'s fetch changes.
- The README's "about 10 seconds" is fair (12 s measured).
- The archive README edit is accurate.
