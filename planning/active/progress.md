# Progress — FWA_WatershedAtMeasure: exbc CTE missing from non-lake path (#1)

## Session 2026-10-13

- Plan-mode exploration — phases approved by user
- Created branch `1-fwa-watershedatmeasure-exbc-cte-missing` off `newgraph` (fork convention; the upstream branch `fix-watershedatmeasure-exbc` comes off `upstream/main`)
- Scaffolded PWF baseline from issue #1 with approved phases
- Next: start Phase 1
- Phase 1: branch `fix-watershedatmeasure-exbc` off `upstream/main` (still 8b3904e), in a worktree. Two commits: d222a91 (migration `202610131450__fix_watershedatmeasure_exbc.sql`) and fc63f79 (`schema.sql` hunk, +16)
- Phase 2: four areas reproduce and the unfixed body errors; the migration applies, re-runs as a no-op, and keeps the comment; the fixed `schema.sql` loads. Scratch schema and DBs dropped. See findings
- Plan review in (`review-plan.md`): no blockers; adopted O1 (code-check before push) and the widened leak grep
- Next: code-check rounds on the upstream branch, then push, cherry-pick, write the draft
