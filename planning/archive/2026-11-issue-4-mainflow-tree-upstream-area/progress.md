# Progress — Upstream area on the main-flow tree, so SSN additive functions need no hand overrides (#4)

## Session 2026-11-20

- Plan-mode exploration — phases approved by user
- Created branch `4-upstream-area-on-the-main-flow-tree-so-s` off origin/newgraph (28fb2ac)
- Scaffolded PWF baseline from issue #4 with approved phases
- Issue body re-read before the baseline (last edited 2026-11-20T05:27Z, no comments): it matches the
  body the plan was built from
- Phase 1: the function's empty answer traced and filed (#52); the lookup re-measured; the whole build
  prototyped province-wide; the Plan review returned (review-4.md) and was folded into the plan. Two
  owner decisions on the way: the corrected count of gaps (reported) and the length share for streams
  with no polygon (asked, decision 7). Commits 91d9437, 3fe9eb1
- Phase 2: tests written before the build (cbac70a)
- Phase 3: `sql/mainflow_tree_area.sql`, about 5 min province-wide, run from `mainflow_tree.sh` (c3be52c)
- Phase 4: `sql/qa_area.sql`, the comparison with the lookup by routing; one build defect found by it
  and fixed (a connector ending a run); 13 restore-the-bug checks fire; #33's body updated (89c7a24)
- Phase 6 (ahead of 5, while SSNbler runs): README and research file (0f2d7f8, fdd5bc5)
- Phase 5 in progress: the pinned SSNbler fork installed; the area step added to `ssnbler_check.R` and
  `ssnbler_check.sh` (switched on by `SSNBLER_AREA=1`, exit status 6 when it fails); clean on a
  3,190-line tributary basin; KLUM running
- Phase 5: KLUM clean; the lookup's area on KLUM's network fails the side-channel check (30f2846)
- Phase 7: `./mainflow_tree.sh` end to end, 46 min 34 s, every test `t`
- `/code-check branch`: five rounds (1aacbf1, 55ca8dd, 6dcacac, e3ea45f, 97e99ed and the commits between).
  Rounds 3 to 5 each found a polygon rule that went by codes where geometry disagreed; the rules now
  move a polygon only to a segment that lies in it. Three owner decisions on the way (8, 9, and no
  whole-Skeena SSNbler run). Seven reviewer agents in all
- Filed on the way: #52 (the function's empty answer), #53 (side channels and floodplain, the owner's
  question), and an issue in the dotfiles repo about a stale GitHub token in long-lived shells
- SSNbler suite on the final build: four subsets clean, values equal to plain arithmetic on every edge
- Review verdict written (five rounds, ended on an enumeration), planning archived, PR #54 opened into `newgraph`
- Next: the merge is the owner's; after it, close #4 by hand and run LSKE where there is memory
