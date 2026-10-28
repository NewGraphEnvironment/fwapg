# Code-check round 2: #24 diversions (ce4add3...HEAD)

## Checklist read

- code-check-infra.md: in full.
- code-check-python.md: in full.
- code-check.md: the prose of all 14 H3s under `## Mechanisms`, `|` table rows skipped. Outside Mechanisms, I read only the index lines.
- code-check-shell.md: I read 13 headings: "Quoting", "Heredoc precedence in pipelines", "A heredoc whose body contains its own delimiter ends early", "`mktemp` template needs enough X's", "A second `trap … EXIT` replaces the first" (the bash 3.2 exit-0 paragraph included), "psql does not interpolate `:'var'` inside a dollar-quoted string, and `\quit N` exits 0", "`exit` inside a loop condition ends the shell", "A value validated with one numeric grammar and consumed with another", "A Python CLI redirected to a log writes nothing until it exits", "A failed `cd` lets every later command run in the directory you were already in", "Paths", and "A sed/awk range can run to EOF". The rest (about 70) I judged from the index: git, gh, S3, awk, ssh, docker and the like.
- code-check-r.md: I read 1 heading: "Postgres row order is never fixed unless the query fixes it". The rest (about 110) I judged from the index: R language, packages and DBI.
- code-check-spatial.md: I read 4 headings: "FWA `upstream_route_measure` misses the next segment's start", "FWA main flow is not edge type 1000 alone", "A Freshwater Atlas main stem's downstream end lies on the receiving river's centreline", and "A name is not a key: `GNIS_NAME`". The rest (about 95) I judged from the index: terra, sf, GDAL and bcdata.

All DB queries were read-only SELECTs on `whse_basemapping.*`.

## Findings

- **[severity: fragile]** extras/pcic_crosswalk/sql/qa.sql:315 (test "a diversion's area comes off its position parent's sub-basin, not its flow parent's"). The first predicate, `r.local_area_ha > r.upstream_area_ha - t.upstream_area_ha`, stands in for "the diversion's area was not taken off R". It is equivalent to that only while R's other FWA children add up to less area than the diversion, and while R does not lie downstream of the diversion on the FWA.
  - The topology 06 accepts. 06's guard 2 refuses a diversion only when `position_parent_subid = anchor_subid`. So 06 accepts a diversion whose PCIC ancestor R lies further down the FWA path than its position parent P, which is PCIC sending a lake out another arm that rejoins the river below P.
  - What the code does there is correct. R's FWA children (by position) include P, or a chain of outlets that contains P. P's upstream area includes the diversion's.
  - What the test then reads. `R.local = R.up - P.up - ... <= R.up - t.up`, so the test reads f on a correct build.
  - Nechako passes on the size of the areas, not on the property. R = 1008709 sits on 0.84 km² of FWA area against the diversion's 13,998.87 km² (both measured on `fwa_watersheds_upstream_area` at segments 700626260 and 701799415). M3 still turns it red, as findings.md records.
  - It fails toward a stop, not a pass. But the next diversion anyone lists may stop the job at QA on a correct build, with no hint why.
  - Suggested fix: test R against its definition instead: `r.local_area_ha` within 0.01 of `r.upstream_area_ha` minus the upstream areas of R's FWA children that are not diversions. Keep the P half as it is.

## Notes (not defects)

- **README forward references to a caveat that does not exist yet.** README.md:114 ends "One is listed: the Nechako Reservoir (below)." The comment at qa.sql:276 ("Measured after: see the README's caveats") points to the same place. The README's Caveats section (line 459 on) has no Nechako entry yet. It is the open Phase 4 item in task_plan.md ("a Nechako Reservoir caveat …"). If the PR goes out without it, both references point at nothing.
- **pcic_crosswalk03_diversions.sql:15, "Unlisted, every outlet above 1007550 broke the chain (479)".** findings.md says something different: "The 479 broken-chain outlets of the four groups are all anchored to 1007550". It also lists 4 `no_candidate` outlets in UEUT, and 4 placed outlets in UNRS and LNRS. If any of those 8 lie above 1007550 in PCIC's tree, "every" overstates. I could not check this without the staging or `pcic.*` tables, which were off limits this round.
- **planning/active/logs/nechako_measure.sql:821.** `ORDER BY min(seg.label) = seg.label, 1` is TRUE for every group, because `label` is a GROUP BY key. So the key points print in alphabetical order, not in the VALUES order (top of the reservoir down to the Cheslatta). The values are unaffected, and the baseline was printed the same way, so before and after still compare.

## Checked and clean

- **The new and edited QA tests.** None can pass vacuously.
  - The job fails any result that is not `t`, NULL included (`grep -qv '|t$'`, pcic_crosswalk.sh:387).
  - Every new test either requires `count(*) > 0` or wraps scalar subqueries in `coalesce(…, false)`.
  - Each scalar subquery returns at most one row: a single subid, or `LIMIT 1`.
  - "exactly one segment" counts `w.linear_feature_id` over a LEFT JOIN, so 0 matches gives n = 0, which reads f.
  - "Eutsuk" and the area test use inner joins with no fan-out, keyed on subid, or on subid and month.
  - The edited "FWA child on another blue line" test excludes only the diversion as the child. Its children are still tested.
- **Key-point literals resolve to the places their labels name.** I checked each on `fwa_stream_networks_sp`:
  - 288852.5 is exit segment 701799415 (Knewstubb Lake 329318438, drm 288852.348).
  - 288500 is the canyon segment 701799355, directly below it. Its upstream area equals the exit's (13,998.87 km²), so the canyon's share is 0 by construction, and the `< 0.1` threshold is not borderline.
  - The Cheslatta joins the Nechako at 280379.359, the start of segment 700641138. So 280500 is above the confluence, and 280000 is below it on 700640507.
  - 503000 is in Whitesail Lake, 400000 in Ootsa/Intata, 330000 in Natalkuz, and 1860 is the top segment of the spillway line 356209076.
- **nechako_measure.sql.** The specific-runoff factor is right: m³/s per km² × 31,536 = mm/yr. `segment_weights` has one row per segment, and `discharge_monthly` is filtered by run in the ON clause, so `avg` is over the run's 12 months. `fwa_streams_watersheds_lut` is 1:1 on the segments checked.
- **The diversion row in 04's depth loop.**
  - It enters `best` only at its own depth, through `outlets`, and is kept out of the candidate branch by `NOT EXISTS`, so there is no duplicate primary key.
  - Its children resolve their anchor to it through `p.linear_feature_id IS NOT NULL`.
  - Its NULL `candidate_rank` and 70 km `distance_to_stream` are read only by reports: qa_report's snap block now excludes diversions, qa_drainage and review_sample filter on `candidate_rank > 1`, and review_build carries the value through.
  - qa_following skips lake outlets, and 03 refuses a diversion that is not a lake outlet, so the "placed share" check cannot see it.
  - 05 never sees it as a broken `s`, because it is always placed, and never blames it as `a`. When a child of the diversion breaks, nobody is demoted, which is the intent.
  - 04's DDL block still ends at a line starting `);`, so pcic_test.sh's sed range (lines 192 and 480) stays bounded.
- **The README and research text.**
  - Step 4, step 5, step 6's diversion sentence, the `fwa_parent_subid`, `distance_to_stream` and `candidate_rank` rows, and research/pcic_routed_flow_periods.md:30 all match 03, 04, 06 and 07.
  - The general `share` formula at README:129 does not cover the canyon segments. The diversion sentence added to step 6 states that exception.
- **mutation_checks.sh against code-check-shell.md.**
  - One EXIT trap, `mktemp … XXXXXX`, and both heredocs quoted with a delimiter (`PY`) that neither body contains.
  - `JOB`'s path depth resolves to `extras/pcic_crosswalk`.
  - `DATABASE_URL` is read before the trap is armed, so the bash 3.2 "armed trap turns an unbound variable into exit 0" case cannot reach it.
  - Mutations patch a fresh copy, which is refused unless the edit matches once.
  - M4's `|| echo` is the only status that is suppressed.
  - M5 now has the convergence check that round 1 noted was missing.
  - The `;\s*\n` statement split in `qa()` does split at qa.sql:106, where a comment ends in `;`. That fragment is comments only, and no picked test is affected.
  - Every regex given to `qa()` matches the test names it is meant to pick, after `''` is unescaped.
