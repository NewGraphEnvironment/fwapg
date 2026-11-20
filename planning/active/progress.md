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
