# Progress — PCIC crosswalk: build routed flow for a chosen model, scenario, years and time step (#25)

## Session 2026-10-17

- Plan-mode exploration — phases approved by user. Plan-gate decisions: `pcic` schema with run columns (folds in #23), calendar month-day bins, sub-basin daily + segment weights as the daily output.
- Created branch `25-pcic-crosswalk-run-parameters` off `newgraph`
- Scaffolded PWF baseline from issue #25 with approved phases
- Next: Phase 1 probes; Plan-agent review of task_plan.md runs concurrently

- Phase 1 probes done (commit 268c09c). The Plan review (planning/active/review-plan.md) landed at the same time; 18 findings, verdicts in the file.
- All 18 CMIP6 series (9 GCMs x 2 scenarios) are gregorian, 55,152 steps, 37 Feb 29s.
- Phases 2-4 written as one commit (`pcic_crosswalk.sh` carries all three):
  - run parameters with a preflight, a missing-value check per batch and a missing-count gate;
  - daily climatology cache per run, `pcic_crosswalk01_days.sql`;
  - daily sub-basin accumulation (set-based per FWA level), weights in 07, period means in 08, segment flow in 09 per group, `qa_weekly.sql`, `qa_report_clamped.sql`;
  - `load/pcic_schema.sql`, `sql/pcic_export.sql`, `load/pcic.sql`, `load/pcic_run.sql` and load.sh;
  - run-aware `qa_gauges.sh` (WSC cache per period) and `qa_gauge.sh`.
- Checked before the builds: day bins (22,646 days, 16 Feb 29s, week 9 = 450, week 52 = 496), the week-bin QA test, and the pcic DDL on the local DB.
- Next: builds from a frozen worktree. 1981-2010 WEEKLY=1 first, the reference 1951-2012 last (review finding 6).
