# Code check, round 2: fwapg#7 drainage check (staged diff)

Scope: `git diff --cached`. I read qa_drainage.sql (new), qa.sql, pcic_crosswalk.sh, README.md, planning/active/*.md and review-round1.md in full. I checked the diff against the relevant checklist sections: Mechanisms (a guard that fails toward pass, one fact derived twice, restore the bug and prove the guard fires), Docker/Postgres, psql, and documentation staleness. All queries against the local DB ran in read-only transactions.

## Clean

No issues found.

## Round-1 fixes re-checked, including one axis over

- **The `unmeasured` flag (fix 1) fires.** I restored the bug against `fwapg.pcic_qa_drainage`: with half of the FWA areas nulled, 18,513 main-stem rows got a NULL ratio, so they would be `unmeasured` and the test would fail. If the area table is empty, the province median is NULL, every ratio is NULL, and the test fails too.
- **One axis over: rows dropped by an INNER JOIN instead of given a NULL ratio.** None can be dropped.
  - `pcic_length`: `up` seeds every outlet, so every subid has a row.
  - `pcic_flow`: pcic_crosswalk04_select.sql (lines 83 and 113) places an outlet only if it has a monthly series. The 28 outlets without one are all flagged `no_series`.
  - `fwa_stream_networks_sp`: placements come from candidates on that table.
  - Checked: 37,667 rows in the table, the same as the 37,667 placed outlets, and 0 placed outlets have no monthly rows.
- **Mirror risk: does the 0-unmeasured rule abort the job on healthy data?** No.
  - 0 of 74,253 main-stem candidate segments lack an FWA area.
  - `fwa_watersheds_upstream_area` has no zero or NULL areas and no duplicate keys, so `ADD PRIMARY KEY (subid)` cannot fail on fan-out.
- **Province median fallback (fix 3).** A group with no qualifying rows gets `r.n` NULL, and `CASE WHEN NULL >= 20` takes the ELSE branch, so it falls back to the province median correctly. The count `n` and both medians come from the same population (`main_stem AND fwa_area_km2 > 0`).
- **Counts (fix 2).** These agree with the DB: 218 small, 124 big, 37,325 NULL-flag rows (36,698 ok + 627 side channels), 0 unmeasured. The figures match in the qa_drainage.sql header, the qa.sql comment, README.md and findings.md.
- **The seeded margins exceed the ceilings.** 218 + 200 is more than 300, and 124 + 198 is more than 200.
- **Shell wiring.** qa_drainage.sql runs under `ON_ERROR_STOP=1` and `set -e`, so a failed rebuild cannot leave a stale table for qa.sql to read. The new test name contains no `|`, so the `'|t$'` parse still works. `data/qa_drainage.csv` is gitignored (`.gitignore:10`).
- **Planning.** The #8 comment that task_plan.md marks done exists and carries the same 218/124 counts.
