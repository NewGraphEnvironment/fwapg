# Progress — FWA_WatershedAtMeasure: exbc CTE missing from non-lake path (xborder regression) (#1)

## Session 2026-10-13 (round 2)

- Plan-mode exploration; phases approved by the user, with scope Middle
- Created branch `1-watershedatmeasure-drop-exbc` off `newgraph` (33779a0)
- Scaffolded the PWF baseline from issue #1 with the approved phases
- Next: Phase 1 (upstream branch off `upstream/main`)
- Phase 1: upstream branch `watershedatmeasure-drop-exbc` (4777ee9 migration, 70c1b79 `schema.sql`) off `upstream/main`
- Phase 2: areas and geometries unchanged at the four points; migration applies on scratch DBs, re-runs as a no-op and keeps comments (findings, "Round 2 results")
- Phase 4 (first step): f2aba13 reverts round 1; 6e9ed8e and a776190 cherry-pick round 2. `db/` equals the upstream branch
- Phase 3: upstream PR drafted in `upstream_pr.md`, held for approval
- `/code-check branch` (base `origin/newgraph`) round 1 running
