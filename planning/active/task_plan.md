# Task: fwa_indexpoint(): an exact distance tie on one stream is broken by row order (#39)

`fwa_indexpoint()` keeps one segment per stream with `DISTINCT ON (blue_line_key) ... ORDER BY
blue_line_key, distance_to_stream` (`db/schema.sql:2409`, `:2442` at ae8f7c7). When two segments of
one stream are exactly the same distance from the point (the point is nearest the node they share),
the ordering does not decide between them, and PostgreSQL returns whichever row its plan reaches
first. The outer `ORDER BY distance_to_stream asc LIMIT $3` (`:2445`) can tie the same way at the
cut, on the distance rounded to 3 decimals.

## Decided at the gate (user, 2026-10-24)

- **Tie rule: the upstream segment.** Inner `ORDER BY blue_line_key, distance_to_stream,
  downstream_route_measure DESC, linear_feature_id`; outer `ORDER BY b.distance_to_stream asc,
  linear_feature_id` (the unrounded distance, from the plan review). Replaces the issue's
  "lowest id", which picks the downstream segment in both measured cases.
- **Two branches** (CLAUDE.md, overriding the issue's "no second branch"): `indexpoint-tiebreak`
  off `upstream/main` carries only the migration and test, for smnorris; `39-indexpoint-tiebreak`
  off `newgraph` carries this PWF and the cherry-pick, with a PR into `newgraph`.
- **The local loaded fwapg is not changed** until the user says so; every check rolls back.
- **Nothing is posted upstream** without the user's explicit go-ahead.
- **Measure the effect downstream of fwapg** (bcfishobs, bcfishpass) before anything goes upstream:
  the user's concern that Simon's runs may have been jumping because of this (added mid-run).

## Phase 1: Upstream branch (clean)

- [x] Add the `upstream` remote; `upstream/main` == `origin/main` (ae8f7c7)
- [x] `indexpoint-tiebreak` off `upstream/main`; `create_migration.sh indexpoint_tiebreak`
- [x] Migration `db/migrations/202610240132__indexpoint_tiebreak.sql`: body verbatim from
      `schema.sql:2373-2448`, only the two `ORDER BY`s changed; `schema.sql` untouched
- [x] `tests/test_FWA_IndexPoint.sql`: two gauge tie cases and a `FWA_LocateAlong` case
- [x] Verify, `/code-check` (3 rounds, clean), commit `d955688` with no `#N`, no `planning/`, no session trailer
- [x] Push to origin and confirm the ref

## Phase 2: newgraph branch

- [x] PWF baseline on `39-indexpoint-tiebreak` off `origin/newgraph` (`d30b15e`)
- [x] `git cherry-pick -x d955688` (`aa9f6a1`)
- [x] Measure bcfishobs and bcfishpass exposure (findings.md)
- [x] Edit #39's body: the tie rule and why, two branches, measurements, downstream exposure
- [x] File a fresh issue: `frs_point_snap()`'s lowest-id tie rule disagrees with fwapg's `[ds, us)` (fresh#266)

## Phase 3: PRs

- [ ] `/planning-archive`, then `/gh-pr-push` → PR into `newgraph`
- [ ] Upstream PR draft and compare link shown to the user. **Not posted.**

## Owed at the end (reported, done after merge)

- [ ] Post the upstream PR, **only on the user's go-ahead**, then link it in #39
- [ ] Close #39 by hand after the newgraph merge, with a comment naming the PRs
- [ ] Apply to the local loaded fwapg **when the user says so**, with `cd db && DATABASE_URL=... ./migrate.sh`.
      It has no `fwapg.db_version`, so that also applies `202610131654__watershedatmeasure_drop_exbc.sql`
- [ ] Draft (not post) a note to Simon on the same tie in bcfishobs `process.sql` and bcfishpass PSCIS snapping, if the user wants one

## Validation

- [x] Tests pass (all 10 `t` with the migration in a rolled-back transaction; 2 `f` on the old function)
- [x] `/code-check` clean
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

**Verification** (all in transactions that roll back):

1. The migration applies, and the tests pass; the old function fails the 08KD006 and LocateAlong cases.
2. The old answer flips with the plan (index scans off) and the new one does not.
3. Old against new on 1,242 points: only exact same-stream ties change segment, and the stream set never changes.
