# Progress — Article with interactive maps: does the main-flow tree's upstream area make sense on the ground? (#55)

## Session 2026-11-20

- Plan-mode exploration — phases approved by user
- Created branch `55-article-with-interactive-maps-does-the-m` off origin/newgraph
- Scaffolded PWF baseline from issue #55 with approved phases
- Next: start Phase 1
- Plan review (Plan agent, 22:31 UTC) returned 13 findings; each probed and folded into `task_plan.md` (`review-plan.md`). Case 1's numbers are per segment (53,007 on 123039830), and its water reaches main flow through side channel 360216962 at 123043992.
- gq upgraded to 0.24.0 (pak needed the stale shell `GITHUB_PAT` unset). Filed NewGraphEnvironment/gq#123; branch `123-imagery-basemap-esri-satellite` in gq under `/code-check`.
- #55 body edited to the gate decisions.
- Phase 2: `mainflow_tree_area.Rmd` with a `checks` chunk keyed on `linear_feature_id` and one README number per case; a copy with 123039830 changed to 53,107 ha stops the render ("check failed: case 1: 123039830 reads 53,007 ha").
- Phase 3: `sql/case1.sql` to `case7.sql`, `case3_search.sql`, `confluence_share.sql`, `article_extract.sh`; extracts written (2.2 MB) and every check passes with `DATABASE_URL` unset.
- gq#123 `/code-check`: round 1 clean; round 2 found World Imagery's z19 placeholder (fixed, maxzoom 18); round 3 found z18 missing north of about 59.15 N, inside round 2's fix (docs narrowed, kept 18); round 4 running as the enumeration.
- gq: `/code-check` ended by enumeration after 5 rounds (round 4 listed every value the Esri styles take from the service; round 5 re-verified it; its one wording finding fixed and probed). PR NewGraphEnvironment/gq#124 opened; the article pins gq@02c6531.
- Phase 4: maps with `case_map()` (fitted to each case's own features), the confluence-share chart (ECDF, log scale; palettes validated with the dataviz skill's validator), `article_render.sh` (refuses without `esri_satellite`, prints the pinned install).
- Phase 5: screenshots read (scratchpad, SwiftShader); per-case readings written. Case 7 is explained: local codes out of order on line 360860536; the 1.632 ha difference is exactly polygons 8628560 and 8632200, which the tree gives to 212038745. Case 6's outlet is on BC's edge at the Alaska border (only TUTR within 5 m of the mouth).
- #53's body gained the case-3 findings; filed #57 (the QA leaves 212038783 unclassed though its cause is out-of-order local codes).
- Validation: a copy with one wrong value stops the render (Phase 2); a git worktree of 9c86123 renders with DATABASE_URL and PGSERVER unset (exit 0, 5.2 MB) and leaves the tree clean.
- Branch `/code-check` round 1 (5 findings, all real): case 6's 42 m and 77 m were closest approaches, not mouth distances (mouth 351 m from 212039249, mouths 166 m apart); the checks did not cover the extract-derived numbers in the prose (now checked; the "every number" sentences narrowed); the case-2 check was circular (now tests codes and the midpoint, with `localcode`/`wscode` added to the streams extracts); `confluence_share.sql` sums unordered (one CSV row changed once ordered); a host name in two plan files (removed).
- Writing case 3's checks showed the side channel is the **edge** of both the "midpoint inside" and "midpoint outside" polygons (3,409 m and 113 m on their boundaries); the midpoint test splits them by floating point (4e-11 m inside, 0 m outside). Case 3 relabelled and rewritten; #53's body corrected.
