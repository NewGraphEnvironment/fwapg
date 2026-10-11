# Progress — Publish PCIC crosswalk outputs to fresh-bc and load them in load.sh (#9)

## Session 2026-10-11

- Plan-mode exploration — phases approved by user
- Created branch `9-publish-pcic-crosswalk-outputs-to-fresh` off `newgraph`
- Scaffolded PWF baseline from issue #9 with approved phases
- Next: start Phase 1

- Phase 1: `load/fwa_stream_networks_discharge_monthly.sql` and `load/pcic_fwa_crosswalk.sql` (create if missing, truncate and `\copy` from `fresh-bc/fwapg/extras/` in one transaction), run from a fork-only section of `load.sh`
  - Failing check: scratch DB `fwapg_issue9`, load gives `curl: (22) … 403`, psql exits 3, and the table is rolled back (`to_regclass` NULL)
  - Guard proof: a populated table (1 row) keeps its row after a failed load; with `BEGIN`/`COMMIT` stripped, the same failure leaves 0 rows
