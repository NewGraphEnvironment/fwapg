# Plan review for #55 (Plan agent, spawned 2026-11-20 22:31 UTC)

Findings as the reviewer gave them, each with the verdict after a probe.

1. **Blocker: gq imagery work already exists.** Stale: it saw this session's own in-progress gq branch (gq#123, `esri_satellite`). Folded: the plan now names gq#123 and `esri_satellite`, not `esri_imagery`. NEWS.md was edited and then reverted, since gq writes NEWS at release; `git status` now shows the three files.
2. **Blocker: case-1 checks name blue_line_keys but quote per-segment numbers.** Confirmed by query: 360216952's bottom two segments read 53,058; 53,007 is 123039830; 1,580 is 123039759 and 123039469. Folded: checks keyed on linear_feature_id; the lookup range for 360216952 is 5.06–5.11 M ha.
3. **Gap: case 1 does not reach main flow.** Confirmed: 123041439 drains through side channel 360216962 (8 segments) to main flow at 123043992; 123043588 is the side-channel mouth `qa.sql` tests. Folded.
4. **Gap: the lookup share is defined nowhere in code.** Accepted. Folded: defined in the extract SQL over the same inflow set, with NULL-lookup inflows counted and reported.
5. **Gap: the case-4 check is circular.** Accepted. Folded: hard-coded expectations (method `lower`, blk 359572098, about 767,000 ha); the article says `lower` does not use the midpoint test.
6. **Gap: case 6 cannot tell a dead-end outlet from a coastal one.** Confirmed by query (dead_end junction 90, dead_end NULL 383, cut_off 3/4/1, no_parent 23). Folded: join `fwapg.mainflow_tree_qa`.
7. **Assumption: cases 2, 3 and 5 not chosen deterministically.** Accepted. Folded: written selection rules per case.
8. **Acceptance: README numbers only partly covered.** Accepted. Folded: one quoted number and check per case.
9. **Acceptance: the clean-checkout render depends on an unmerged gq branch.** Accepted. Folded: `article_render.sh` checks for `esri_satellite` up front and prints the pinned install.
10. **Ordering: checks written before the extract's files exist.** Accepted. Folded: Phase 2 fixes file names and columns; the red step is a stub extract with one wrong value.
11. **Gap: the floodplain step is not ogr2ogr.** Accepted. Folded: an R step filters ff04, keeps both `in_wsg` sides, clips, writes sorted GeoJSON.
12. **Scope: no size budget.** Accepted. Folded: cap of 10 MB for extracts; no simplification of segments (it moves midpoints).
13. **Assumption: headless WebGL.** Accepted. Folded: SwiftShader flags, screenshots to the scratchpad.

## Files the plan names
extras/mainflow_tree/README.md
extras/mainflow_tree/sql/qa.sql
extras/mainflow_tree/sql/qa_area.sql
.gitignore
