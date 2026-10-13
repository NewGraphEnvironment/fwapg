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
- Code-check on the upstream branch (findings in `review-round1.md`, `review-round2.md`, `review-round3.md`):
  - Round 1: one point. The framing treated PR 185's removal of the CTE as accidental, though its notes suggest it was intended. The draft now offers both fixes.
  - Round 2: clean. Every draft claim was checked.
  - Round 3: the `newgraph` side is clean, and the cherry-pick is clean (tested in a throwaway clone). It also enumerated every place the "accidental" claim appeared: the #1 body (lines 3, 63, 85), and `task_plan.md` and `findings.md`, which copy it.
  - All of these were reworded. A grep for "accident" across the upstream branch's messages and diff, the PWF branch's tree and messages, and the #1 body now returns 0. That enumeration ended the loop.
  - `origin/fix-exbc-nonlake` (4708405) still says "accidentally removed". It is retired after the upstream PR is posted, as planned.
- Phase 3:
  - Pushed `fix-watershedatmeasure-exbc` (fc63f79) to `origin`.
  - Cherry-picked it onto the PWF branch as a616f45 and 627050e. The diff outside `planning/` is byte-identical to `upstream/main...fix-watershedatmeasure-exbc`.
  - No separate `/code-check branch` was run on the PWF branch: its code diff is identical to the one rounds 1–3 reviewed, and the rest is planning files.
  - Ticked #1's done boxes (branch, migration, schema.sql, test, migrate.sh, push and draft).
- Left for the operator:
  - approve and post the upstream PR, choosing option 1 or 2 and deciding on the `Claude-Session:` trailer;
  - merge the `newgraph` PR;
  - after posting, retire `fix-exbc-nonlake`.
