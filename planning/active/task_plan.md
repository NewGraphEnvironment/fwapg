# Task: fwa_indexpoint(): one tie rule and measure method across point matching, with smnorris/fwapg#86 filters and smnorris/fwapg#161 z (#41)


smnorris/fwapg#201 (the tie-break from #39) was reviewed on 2026-10-24. Simon asked for two things before the migration lands:

1. Compare its tie-break with the other queries that match points to streams, so they all break the tie the same way. Possibly by using `fwa_indexpoint()` everywhere.
2. Fold in the enhancements in smnorris/fwapg#86 (options for which streams are returned) and smnorris/fwapg#161 (the returned point has no z).

#39 is done and archived. This issue is the revision that grows out of the review, and it lands on the same upstream branch (`indexpoint-tiebreak`), so smnorris/fwapg#201 carries one migration rather than two.

## Context from exploration

What exploration added (probes against the loaded provincial fwapg, read-only, 2026-10-24):

- **`ST_LineMerge` drops M** on this PostGIS 3.5.2 / GEOS 3.9.0 (`ST_NDims` 4 → 3). The column is already `geometry(LineStringZM, 3005)`, so the merge does nothing useful, and it is the reason the current function cannot return M.
- `ST_M(ST_LineInterpolatePoint(geom, f))` agrees with bcfishpass's `ST_InterpolatePoint` to within 2.3e-10 over 74,274 sampled points.
- `upstream_route_measure` is generated as `downstream_route_measure + ST_Length(geom)`, and it equals the end M. `length_metre` is the source attribute, so the formula `drm + f * length_metre` can run past `upstream_route_measure` into the ~mm gap before the next segment. `FWA_LocateAlong` places a measure by M (`ST_LocateAlong`) and filters segments on `[drm, urm)` rounded to 4 dp. The formula's measure and its point therefore disagree, and near a segment top `FWA_LocateAlong` finds nothing.
- At 08KD006 both lower-segment measures return 0 rows from `FWA_LocateAlong` (14040.0049 is above the lower segment's `urm` after rounding). Only the tie-break fixes that vertex. The measure method fixes interior and near-top points.
- `fiss_stream_sample_sites_events.sql` computes the measure by formula, then places the point by M. It already filters `localcode IS NOT NULL AND NOT wscode <@ '999'` before its pick, which is exactly #86's two options set to false.
- Only `postgisftw.fwa_indexpoint` calls the function inside fwapg. Its body is a SQL string, so no dependency blocks a DROP.

## Decided at the gate (user, 2026-10-24, AskUserQuestion at plan mode)

1. **#86 scope:** `include_disconnected` and `include_null_localcodes`, applied inside the 100-nearest window before the per-stream pick, both defaulting to `true` (today's behaviour). `match_type = flow`, a better `bc_ind` and a marine flag stay out.
2. **Measure and point:** drop `ST_LineMerge`; point = `ST_LineInterpolatePoint(geom, ST_LineLocatePoint(geom, pt))`, returned as XYZM; `downstream_route_measure = ST_M(point)`. This closes #161. Known break: a caller writing `geom` into a 2D-typed column needs `ST_Force2D`. The PR says so.
3. **Outside fwapg:** document the rule in fwapg docs. Draft, but do not post, notes for bcfishobs and bcfishpass.
4. **channel_width:** both picks call `fwa_indexpoint(..., false, false)` instead of hand-rolled SQL.
5. **Stream head (user, 2026-10-24, mid-run).** With the geometry-M measure, a point snapped to a stream's head has `downstream_route_measure` equal to its top segment's `upstream_route_measure`, which `FWA_LocateAlong`'s `round(upstream_route_measure, 4) > measure` rejects. `FWA_LocateAlong` takes `FWA_WatershedAtMeasure`'s rule instead: the highest `round(downstream_route_measure, 4) <= measure` on the blue line, with no upstream bound and the 4 dp rounding kept. Junction ties resolve as before, the head becomes locatable, and a measure in a gap or past the head still returns nothing.

Mechanics, chosen by me (amend at approval if wrong):

- The tie rule stays as in d955688: `distance, downstream_route_measure DESC, linear_feature_id`.
- The migration file keeps its name `202610240132__indexpoint_tiebreak.sql`; its content is replaced. It has not been applied anywhere we know of, local fwapg included.
- The migration DROPs and recreates both functions, because adding parameters with defaults to the same name would make a 3-argument call ambiguous. Both COMMENTs are recreated.
- The rework is a **new commit on top of d955688** on `indexpoint-tiebreak`, with no force-push, because Simon has already seen d955688.
- The upstream code is edited in a git worktree of `indexpoint-tiebreak` under the scratchpad. The PWF branch `41-fwa-indexpoint-one-tie-rule-and-measure` is cut from `39-indexpoint-tiebreak`, not newgraph, because #40 is unmerged and carries #39's archive and the research file. The new upstream commits are cherry-picked onto it. Its PR into `newgraph` supersedes #40.
- **Pushing `indexpoint-tiebreak` to origin updates smnorris/fwapg#201 publicly, so it waits for your word.** The same goes for the #201 body edit, the comment to Simon and the bcfishobs/bcfishpass notes: drafted, not posted. Approving this plan covers everything up to the open newgraph PR, and not those pushes or posts.

## Phase 1: Baseline harness
- [x] Worktree of `indexpoint-tiebreak` (confirm it equals `origin/indexpoint-tiebreak`, d955688) in the scratchpad
- [x] Scratch SQL (scratchpad, not committed) that rebuilds #39's point sets deterministically (`setseed`): 242 random BC points and 1,000 points near segment ends. Record the current function's output (lfid, blk, measure, distance) and whether `FWA_LocateAlong(blk, measure)` returns a point
- [x] Load FISS sample sites with `bcdata bc2pg` into a scratch schema, then run the current channel_width SQL against them into a temp table, inside a transaction that rolls back

## Phase 2: Migration (upstream branch)
- [ ] Rewrite `db/migrations/202610240132__indexpoint_tiebreak.sql`: DROP both functions, then CREATE `whse_basemapping.fwa_indexpoint(point, tolerance, num_features, include_disconnected boolean DEFAULT true, include_null_localcodes boolean DEFAULT true)`
- [ ] Body changes: filters in the inner WHERE beside `edge_type != 6010`; no `ST_LineMerge`; XYZM point and its M as the measure; tie rule and the outer sort unchanged from d955688; header comment explaining all three changes
- [ ] Recreate `postgisftw.fwa_indexpoint(x, y, srid, tolerance, num_features, include_disconnected, include_null_localcodes)` and both COMMENTs, after the whse function, its call qualified as `whse_basemapping.FWA_IndexPoint` (review G2)
- [ ] `CREATE OR REPLACE` `whse_basemapping.fwa_locatealong` with decision 5's selection (same signature); header comment says why

## Phase 3: Tests (`tests/test_FWA_IndexPoint.sql`)
- [ ] Returned geom is XYZM, and `ST_M(geom) = downstream_route_measure`
- [ ] Round trip: `FWA_LocateAlong(blk, measure)` is within 1e-6 m of the returned geom, at an interior point and at the 08KD006 vertex
- [ ] `include_disconnected => false` drops a `999` stream (Teanook Lake, 354094227), and the default keeps it (the existing test)
- [ ] `include_null_localcodes => false` drops a null-localcode stream at a point found by probe, where the next stream is recovered and not lost
- [ ] Existing 10 cases still `t`; the 3-argument and 5-argument calls both resolve
- [ ] Premise coverage (user, 2026-10-24: "Confirm tests sufficiently test the premise of the refactor. Make new ones if required to avoid issues found during refactor"). Each premise gets a case, and each case is shown to fail against d955688, or against a body with that one change reverted. The table goes in `findings.md`:
  - M is kept (no `ST_LineMerge`): `ST_NDims(geom) = 4`, and `ST_M(geom)` equals the measure exactly
  - The measure equals geometry M, not the formula: within 1e-9 of `ST_InterpolatePoint(segment.geom, input point)`
  - The point near a segment's top round-trips: a probe-found point whose formula measure lands past `upstream_route_measure` (so `FWA_LocateAlong` returned nothing) now returns a point
  - The filters apply before the per-stream pick: a point where a stream's nearest segment is excluded but another segment of that stream is within tolerance returns that stream on the usable segment, not nothing
  - Defaults keep today's stream set: a 3-arg call and an explicit `true, true` call give identical rows
  - The postgisftw wrapper passes the flags through (a 7-arg call differs from the 5-arg one where the filter bites)
- [ ] Invariants that can fail (review AC1, AC2, AC4): `ST_Zmflag(geom) = 3` and SRID 3005; the measure lies within the returned segment's `[downstream_route_measure, upstream_route_measure]`; the point is within 1e-6 m of `ST_ClosestPoint`; the filter case asserts the stream comes back on its other `linear_feature_id`; the `999` case also asserts that some other stream is returned
- [ ] `FWA_LocateAlong` cases in `tests/test_FWA_LocateAlong.sql`: a stream's head returns a point; a junction measure returns the upper segment's start; a measure in a gap and one past the head return nothing
- [ ] The tests run with `-At -v ON_ERROR_STOP=0`, counting lines that are not `t` plus ERROR lines (review AC5), and include the 1-argument and named-argument calls
- [ ] Any defect found while refactoring (in review or verification) gets a regression case in the same file before its fix lands

## Phase 4: channel_width onto fwa_indexpoint
- [ ] Replace the 10-nearest/150 m pick with `CROSS JOIN LATERAL fwa_indexpoint(pts.geom, 150, 10, false, false)`. Keep the 20k→50k watershed-code match. `DISTINCT ON` the site, ordered by the function's `WITH ORDINALITY` (review G5). Join back to the stream table for `waterbody_key`. Keep `wscode_ltree_lookup` and the column set
- [ ] Replace the second, 100 m single-stream pass with `fwa_indexpoint(pts.geom, 100, 1, false, false)`; geom from the function, keeping the `::geometry(PointZM, 3005)` cast (review G3)

## Phase 5: Docs
- [ ] `docs/03_functions.md` FWA_IndexPoint: both synopses with the new parameters and a parameter table. State the tie rule, the measure from geometry M, the XYZM point, and that the filters apply before the per-stream pick
- [ ] `docs/01_usage.md:185` casts `i.geom::geometry(Point, 3005)`, which errors on a ZM point: fix it. Also fix the stale types and example outputs at `docs/03_functions.md:196,224,241,270-275` and `README.md:52`, regenerated from the new function after Phase 6
- [ ] `docs/03_functions.md` FWA_LocateAlong: state that the selection is the highest segment start at or below the measure, so a stream's head is included

## Phase 6: Verification and research
- [x] Tests run inside `BEGIN; <migration body with its own BEGIN/COMMIT stripped>; \i tests; ROLLBACK`; the strip is checked by grep before the run (review B2). All `t`; each premise case is shown to fail against d955688 or the one-change revert
- [x] Old against new, on Phase 1's point sets with default flags: same blue-line set and the same segment as d955688. Report the maximum measure difference. Count `FWA_LocateAlong` and `FWA_WatershedAtMeasure`-point misses old against new, and report every remaining miss by class (review AC4: the 4 dp band and ties by one ulp can remain)
- [x] Filters: on the PCIC outlets (150 m, 5 streams), compare streams recovered by `false, false` with filtering the defaults' output afterwards, against an independent count from a query using only these two filters before the pick, which must match exactly (review AC3: the 651 includes other causes)
- [x] channel_width old against new on the FISS sites: distinct sites, rows, blue line, segment and measure, plus the `channel_width_measured.sql` join (its `(downstream, upstream]` match). The SQL is run with BEGIN/COMMIT stripped and `fwapg.` rewritten to the scratch schema. Explain every class of difference (tie, window, rows the old `ST_LocateAlong` dropped, rounded distance)
- [x] Timing: old against new on 1,000 points, and the channel_width run
- [ ] Revise `research/fwa_position_codes.md` (the indexpoint sections: ST_LineMerge drops M, the measure method, the filters) and `findings.md`; scratch FISS schema dropped

## Phase 7: Commit upstream, drafts
- [ ] `/code-check` on the upstream diff (`upstream/main...indexpoint-tiebreak`), fixes folded in, then one commit on `indexpoint-tiebreak` with no `planning/`, no NGE numbers and no `Claude-Session:` (local only)
- [x] Draft the #201 body revision (~200 words: bug, change, test table, the 2D-column note, that DROP resets grants, and that pg_featureserv needs a restart to see the new parameters; a database that applied d955688 will not re-run the same timestamp) and a reply to Simon answering his two asks. Draft the bcfishobs `process.sql` and bcfishpass PSCIS/falls/dams notes with file:line and the fix. All in `planning/active/drafts.md`, none posted

## Phase 8: newgraph side and PR
- [ ] Cherry-pick the upstream commit(s) onto `41-…` (each with its checkbox flip)
- [ ] `/code-check branch` over the newgraph branch, fixes as follow-up commits
- [ ] `/planning-archive`, with Measurement, Evidence and Owed sections
- [ ] Push `41-…`, open the PR into `newgraph` (`-R NewGraphEnvironment/fwapg`, says it supersedes #40), close #40 with a comment naming it

## Owed at the end (reported, done after merge)

- [ ] Push `indexpoint-tiebreak` and post the #201 body edit and reply, **on your word**
- [ ] Post the bcfishobs/bcfishpass notes, **on your word**
- [ ] Re-apply the fwa_indexpoint grants on our deployment after the migration (DROP resets them), and restart pg_featureserv
- [ ] Open issues for the NGE picks still on the formula measure: this fork's `pcic_crosswalk02_candidates.sql` (`ST_LineMerge` and formula) and fresh's `frs_point_snap()` (review S1)
- [ ] After upstream settles: merge the newgraph PR, close #39 and #41 by hand naming the PRs, then migrate the local fwapg (`cd db && DATABASE_URL=... ./migrate.sh`) **when you say so**

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean (upstream diff before its commit; `/code-check branch` on the newgraph branch)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Every database run happens inside a transaction that rolls back, so the shared fresh-db is never migrated. The one exception is the FISS sites load, which goes to a scratch schema that is dropped afterwards. A Plan agent reviews `task_plan.md` concurrently once it is scaffolded.

