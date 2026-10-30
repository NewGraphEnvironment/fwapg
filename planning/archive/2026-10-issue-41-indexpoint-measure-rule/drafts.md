# Drafts (#41)

Posted 2026-10-30: section 1 (as revised below, body and title) and section 4 (as the comment). Section 2 was posted 2026-10-24; section 3 was superseded by 4.

Each of these goes out only on the user's word.

## 1. smnorris/fwapg#201 body (replaces the current one)

Title: `FWA_IndexPoint: tie-break, measure from the stream's m, stream filters; one segment rule for measure-taking functions`

> **Bug.** A point nearest the vertex two segments of one stream share ties on distance, and `DISTINCT ON (blue_line_key)` took whichever segment the plan reached first. When that was the lower segment, the measure fell short of the next segment's start: `FWA_LocateAlong` and `FWA_WatershedAtMeasure` returned nothing (gauge 08KD006).
>
> **Change** (one migration, `202610240132__indexpoint_tiebreak.sql`):
> - `FWA_IndexPoint`: ties go to the segment starting at the vertex, then `linear_feature_id`. The point is `ST_LineInterpolatePoint` on the segment, PointZM (#161), and the measure is its m. The old formula (`drm + fraction * length_metre`) differs from m by up to ~5 mm and can name a measure past the segment's m range. `ST_LineMerge` was dropping m. `include_disconnected` and `include_null_localcodes` (#86) apply before the per-stream pick; defaults keep today's rows. A point on a watershed-group boundary no longer errors.
> - At a stream's head the m measure equals the top segment's `upstream_route_measure` (91% of blue lines), which `upstream_route_measure > measure` rejected. `FWA_LocateAlong`, `FWA_UpstreamTrace`, `FWA_DownstreamTrace`, `FWA_WatershedHex` and `FWA_WatershedStream` now take the highest segment whose range, closed at the top, holds the measure. `FWA_UpstreamBorderCrossings` accepts the head and clamps its slice fraction.
> - `extras/channel_width` calls `FWA_IndexPoint` instead of its own pick.
>
> **Tests:** 54 cases across five files, all `t`; each of 13 one-change reverts turns at least one red.
>
> | check | before | after |
> |---|---|---|
> | `FWA_WatershedAtMeasure` point step misses, 1,190 random-point rows | 156 | 0 |
> | `FWA_LocateAlong` misses, 11,182 indexed measures | 1,627 | 34 (4 dp band) |
> | streams / segments changed, default flags | — | 0 / 0 |
> | trace / watershed results changed where both answer (558 measures) | — | 0 |
>
> **Deploy notes:** both `fwa_indexpoint` functions are dropped and recreated, so grants are reset and pg_featureserv needs a restart. `geom` is now PointZM: wrap in `ST_Force2D` for a 2D column. A database that applied the earlier version of this migration will not re-run it.
>
> 🤖 Generated with [Claude Code](https://claude.com/claude-code)

(Numbers from `findings.md`. `FWA_LocateAlong` before = old measure with the old rule, 11,182 − 9,555; after = new measure with the new rule, 11,182 − 11,148.)

## 2. Reply to Simon on #201

> Reworked as discussed. On your two asks:
>
> 1. **Same tie-break everywhere.** `FWA_IndexPoint` now breaks the tie toward the segment starting at the vertex, and `extras/channel_width` uses `FWA_IndexPoint` rather than its own copy of the pick. bcfishobs and bcfishpass don't call it; their picks are listed below if you want them changed to match.
> 2. **#86 and #161.** The two filter options are in, and default to the old behaviour. `match_type = flow` is left out, given the Cowichan case. The point now carries z and m.
>
> The measure now comes from the stream geometry's m, the value `FWA_LocateAlong` and `FWA_WatershedAtMeasure` read. That is the narrow version of the precision question you raised. It does not try to fix rounding generally: `FWA_LocateAlong` keeps its 4 dp comparison. The one change there is that a stream's head is now locatable, because the m measure at a head equals the top segment's `upstream_route_measure`, which the old `<` excluded.
>
> The m measure made a stream's head show up as a gap in every function with `upstream_route_measure > measure`, so those now share one segment rule (closed at the top). `FWA_UpstreamBorderCrossings` keeps its 1 cm junction tolerance.
>
> Found along the way, not changed here:
> - `channel_width_measured.sql` joins events to segments on `(downstream, upstream]`, which drops a measure sitting exactly on a segment start (~450 of 63,500 FISS sites). It also has what looks like a leftover filter, `e.localcode_ltree = '400.536025.503903.677855'`.
> - The second pass of `fiss_stream_sample_sites_events.sql` can insert a site twice when it sits on a watershed-group boundary (the `INNER JOIN` to the groups).

## 3. Note for Simon: the same untied pick in bcfishobs and bcfishpass

Lines from smnorris default branches as measured 2026-10-24 (bcfishobs `main` 217b650, bcfishpass `main` 620dbe4). Re-check the lines before posting.

> None of these breaks an exact distance tie, so a point on a vertex two segments share can take either segment's local code:
> - bcfishobs `sql/process.sql:163` and 7 more nearest-stream picks in the file (`ORDER BY ..., distance_to_stream`). About 2.3% of observations sit on such a tie, 1.1% where the local codes differ.
> - bcfishpass `model/01_access/sql/load_falls.sql:74`, `load_dams.sql:74` (`str.geom <-> pt.geom limit 1`).
> - bcfishpass `model/01_access/pscis/sql/02_pscis_streams_150m.sql:74` (`distance_to_stream`), and `04_pscis.sql:208`, `05_pscis_points_duplicates.sql:80` (name score, then weighted distance).
>
> The one-line fix in each: add `downstream_route_measure DESC, linear_feature_id` after the distance key. Where they compute a measure, `ST_InterpolatePoint` is already the m method.

## 4. Reply after "I'll take a look at the PR in November" (2026-10-30)

Replaces 3 as the comment to post. Post only once the reworked branch is pushed (the Owed list in README.md). Lines re-checked 2026-10-30 against bcfishobs `main` 217b650 and bcfishpass `main` 3bd2824 (the measurement is in findings.md, "Effect on bcfishobs and bcfishpass"). Names no private repo.

> Thanks Simon, no rush at all. We're adding a few things now so they're ready when you get to it in November.
>
> The branch now has the rework: one tie rule, the #86 filters, z/m on the point, and the measure taken from the stream's m. Taking the m exposed a stream-head gap in the functions that take a measure, so those now share one segment rule. Agreed that general float handling is a bigger, separate job; this doesn't attempt it.
>
> Where the equidistant match shows up: in the nearest-stream picks downstream rather than in fwapg. bcfishobs `sql/process.sql:163` (and 7 more in that file), and bcfishpass `load_falls.sql:74`, `load_dams.sql:74` and `02_pscis_streams_150m.sql:74` have no tie-break. About 2.3% of observations sit on a tie, and 1.1% of observations get a different local code depending on which segment wins. Adding `downstream_route_measure DESC, linear_feature_id` after the distance key fixes each.
>
> What this PR changes in bcfishobs and bcfishpass: neither calls `FWA_IndexPoint`. Their only calls to changed functions are 4 `FWA_LocateAlong` sites, all passing whole-number measures. We ran old and new on each site's inputs (current SQL, provincial FWA):
> - bcfishobs `process.sql:539`: 372,424 observations, identical
> - bcfishpass `04_pscis.sql`: 27,590 crossing matches, identical
> - bcfishpass `barriers_user_definite.sql`: 226 barriers, identical
>
> Province-wide, 165 whole-number measures (96 at stream heads) now return a point where they returned none, and none of these inputs lands on one. No point is lost or moved.
>
> An example of the precision issue you mention, unchanged here: 3 observations on blue line 359500676 get measure 900, but the segment starts at 900.0000085, so `FWA_LocateAlong` returns nothing in either version.
>
> After migrating, the grants on your shared database need re-applying, because the `FWA_IndexPoint` functions are dropped and recreated.


## 1 as posted (2026-10-30)

Section 1 with the final counts (56 cases, 15 reverts), the `FWA_SliceWatershedAtPoint` clamp and a bcfishobs/bcfishpass line.

> **Bug.** A point nearest the vertex two segments of one stream share ties on distance, and `DISTINCT ON (blue_line_key)` took whichever segment the plan reached first. When that was the lower segment, the measure fell short of the next segment's start: `FWA_LocateAlong` and `FWA_WatershedAtMeasure` returned nothing (gauge 08KD006).
>
> **Change** (one migration, `202610240132__indexpoint_tiebreak.sql`):
> - `FWA_IndexPoint`: ties go to the segment starting at the vertex, then `linear_feature_id`. The point is `ST_LineInterpolatePoint` on the segment, PointZM (#161), and the measure is its m. The old formula (`drm + fraction * length_metre`) differs from m by up to ~5 mm and can name a measure past the segment's m range. `ST_LineMerge` was dropping m. `include_disconnected` and `include_null_localcodes` (#86) apply before the per-stream pick; defaults keep today's rows. A point on a watershed-group boundary no longer errors.
> - At a stream's head the m measure equals the top segment's `upstream_route_measure` (91% of blue lines), which `upstream_route_measure > measure` rejected. `FWA_LocateAlong`, `FWA_UpstreamTrace`, `FWA_DownstreamTrace`, `FWA_WatershedHex` and `FWA_WatershedStream` now take the highest segment whose range, closed at the top, holds the measure. `FWA_UpstreamBorderCrossings` accepts the head, and it and `FWA_SliceWatershedAtPoint` keep their slice fraction in [0, 1] (at some stream heads the fraction rounded above 1 and the slice errored).
> - `extras/channel_width` calls `FWA_IndexPoint` instead of its own pick.
>
> **Tests:** 56 cases across five files, all `t`; each of 15 one-change reverts turns at least one red.
>
> | check | before | after |
> |---|---|---|
> | `FWA_WatershedAtMeasure` point step misses, 1,190 random-point rows | 156 | 0 |
> | `FWA_LocateAlong` misses, 11,182 indexed measures | 1,627 | 34 (4 dp band) |
> | streams / segments changed, default flags | — | 0 / 0 |
> | trace / watershed results changed where both answer (558 measures) | — | 0 |
>
> **Deploy notes:** both `fwa_indexpoint` functions are dropped and recreated, so grants are reset and pg_featureserv needs a restart. `geom` is now PointZM: wrap in `ST_Force2D` for a 2D column. A database that applied the earlier version of this migration will not re-run it.
>
> **bcfishobs and bcfishpass:** no change. Their only calls into changed functions are 4 `FWA_LocateAlong` sites, and old and new give identical points on their inputs (details in the comment below).
>
> 🤖 Generated with [Claude Code](https://claude.com/claude-code)
