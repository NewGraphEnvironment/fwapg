# Review: pcic_test.sh, round 2

Reviewed 2026-10-18 UTC against the staged diff. The round 1 fixes (non-headwater upstream sub-basin, `same()` export-vs-staging, the daily and weekly reload, the count-prefixed md5 compare) hold: I found no vacuous pass in them. The test passes on the current tree (17.4 s, measured with `time`).

Each "missed" below is a mutation I ran on a copy of `extras/pcic_crosswalk` and `load` (scratchpad `rv2_mut.py`, plus a `mut3` run). Every one exited 0 with `all pcic tests pass`.

## Findings

- **[severity: fragile]** load/pcic.sql:131-134, extras/pcic_crosswalk/pcic_test.sh:12-14. `HEADER MATCH` on the four shared-table `\copy` lines is never tested. Only pcic_run.sql's copy gets a reordered file (line 281). Changing all four lines to plain `header` passes the whole suite (measured). The header says the suite covers "every refusal in ... load/pcic.sql". This refusal is the only guard against a reordered `pcic.day_bins.csv.gz`: month, day and week are all integer, and the only content check on that file is `count(*) != 366`. A reordered weights file is in the same position (`linear_feature_id`/`subid` are both integers, and rows and share sum are unchanged). Either file would load silently into the wrong columns (`code-check-infra.md`, "`COPY ... HEADER` skips the first line unread"). Fix: in `$S/other`, write a day_bins file with the day and week columns swapped, header included, and expect `refused ... 'mismatch' $Q -f "$S/pcic_other.sql"`.

- **[severity: fragile]** extras/pcic_crosswalk/pcic_test.sh:237-238 and :322-323. Each orphan refusal is tested on one of its three source tables. The export's is tested only with a Ghost row in `discharge_monthly`, pcic.sql's only with one in `discharge_weekly`. Measured, all missed:
  - deleting the `UNION ... pcic.discharge_weekly` arm from pcic_export.sql;
  - deleting the `pcic.subbasin_daily` arm from pcic_export.sql;
  - deleting the `UNION ... pcic.discharge_monthly` arm from load/pcic.sql.

  A broken arm fails silently: orphan rows in that table go unchecked and are never replaced, which is what the guard exists to stop. Fix: for each guard, insert the Ghost row into `subbasin_daily`, `discharge_monthly` and `discharge_weekly` in turn, and expect the refusal each time.

- **[severity: fragile]** extras/pcic_crosswalk/README.md:132-138. The README makes claims the test does not back:
  - "Run it after changing ... `../../load/pcic*.sql`": the glob takes in `load/pcic_fwa_crosswalk.sql`, the `whse_basemapping` first-build loader, which the test never runs. Someone changing it would get a green run with no coverage. Name the three files instead (`pcic_schema.sql`, `pcic.sql`, `pcic_run.sql`).
  - "tests the steps after the fetch": steps 2-6 also run after the fetch (`02_candidates` through `07_segments`: snapping, placement, accumulation, weights), and none is tested. The fixture writes `q_acc` and `segment_weights` by hand, exactly the outputs of 06 and 07. Say "the steps from the period flow on" (or list 01, 08, 09, the export and the loads).
  - "about 10 seconds": measured 17.4 s. Minor.

- **[severity: fragile, low]** Three code paths no test reaches. They are listed for completeness; each mutation below makes a guard stricter, which fails loudly in production rather than silently, so none blocks the merge. All missed:
  - pcic_export.sql:32, the exemption that lets a run re-export itself onto a new crosswalk. Removing it refuses the rebuild path the README prescribes.
  - load/pcic.sql:158, the exemption for published runs in the "other crosswalk" check.
  - load/pcic.sql:191, `crosswalk_md5` in the stale-monthly DELETE. Removing it from the comparison passes. The two runs never differ by crosswalk alone, so the fixture cannot reach this one.

No security issues. The cleanup, the fixed scratch DB names and the PGSERVER handling are as accepted.
