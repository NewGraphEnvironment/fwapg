# Drafts (#41) — none posted

Each of these goes out only on the user's word.

## 1. smnorris/fwapg#201 body (replaces the current one)

Title: `FWA_IndexPoint: tie-break, measure from the stream's m, stream filters; FWA_LocateAlong at a stream's head`

> **Bug.** A point nearest the vertex two segments of one stream share ties on distance, and `DISTINCT ON (blue_line_key)` took whichever segment the plan reached first. When that was the lower segment, the measure fell short of the next segment's start: `FWA_LocateAlong` and `FWA_WatershedAtMeasure` returned nothing (gauge 08KD006).
>
> **Change** (one migration, `202610240132__indexpoint_tiebreak.sql`):
> - Ties go to the segment starting at the vertex, then `linear_feature_id`.
> - The point is `ST_LineInterpolatePoint` on the segment, PointZM (#161), and the measure is its m. The old formula (`drm + fraction * length_metre`) differs from m by up to ~5 mm and can name a measure past the segment's m range. `ST_LineMerge` was dropping m.
> - `include_disconnected`, `include_null_localcodes` (#86), applied before the per-stream pick; defaults keep today's rows.
> - `FWA_LocateAlong` takes the highest segment starting at or below the measure (`FWA_WatershedAtMeasure`'s rule), so a stream's head is locatable.
> - `extras/channel_width` calls `FWA_IndexPoint` instead of its own pick.
>
> **Tests:** 26 cases, all `t`; reverting any one change turns at least one red.
>
> | check (BC points, 5 streams) | before | after |
> |---|---|---|
> | `FWA_WatershedAtMeasure` point step misses, 1,190 random rows | 156 | 0 |
> | `FWA_LocateAlong` misses, 11,182 indexed measures (incl. points just below segment tops) | 1,627 | 34 (4 dp band) |
> | streams / segments changed with default flags | — | 0 / 0 |
>
> **Deploy notes:** both `fwa_indexpoint` functions are dropped and recreated, so grants are reset and pg_featureserv needs a restart to see the new parameters. `geom` is now PointZM: wrap in `ST_Force2D` for a 2D column. A database that applied the earlier version of this migration will not re-run it.
>
> 🤖 Generated with [Claude Code](https://claude.com/claude-code)

(Numbers from `findings.md`: `FWA_LocateAlong` before = old measure with the old rule, 11,182 − 9,555; after = new measure with the new rule, 11,182 − 11,148.)

## 2. Reply to Simon on #201

> Reworked as discussed. On your two asks:
>
> 1. **Same tie-break everywhere.** `FWA_IndexPoint` now breaks the tie toward the segment starting at the vertex, and `extras/channel_width` uses `FWA_IndexPoint` rather than its own copy of the pick. bcfishobs and bcfishpass don't call it; their picks are listed below if you want them changed to match.
> 2. **#86 and #161.** The two filter options are in, and default to the old behaviour. `match_type = flow` is left out, given the Cowichan case. The point now carries z and m.
>
> The measure now comes from the stream geometry's m, the value `FWA_LocateAlong` and `FWA_WatershedAtMeasure` read. That is the narrow version of the precision question you raised. It does not try to fix rounding generally: `FWA_LocateAlong` keeps its 4 dp comparison. The one change there is that a stream's head is now locatable, because the m measure at a head equals the top segment's `upstream_route_measure`, which the old `<` excluded.
>
> Found along the way, not changed here:
> - `FWA_UpstreamTrace` and `FWA_DownstreamTrace` have the same `upstream_route_measure >` filter, so they also reject a start at a stream's head.
> - `channel_width_measured.sql` joins events to segments on `(downstream, upstream]`, which drops a measure sitting exactly on a segment start (~450 of 63,500 FISS sites). It also has what looks like a leftover filter, `e.localcode_ltree = '400.536025.503903.677855'`.
> - The second pass of `fiss_stream_sample_sites_events.sql` can insert a site twice when it sits on a watershed-group boundary (the `INNER JOIN` to the groups).

## 3. Note for Simon: the same untied pick in bcfishobs and bcfishpass

Lines from smnorris default branches as measured 2026-10-24 (bcfishobs `master` 217b650, bcfishpass `main` 620dbe4). Re-check the lines before posting.

> None of these breaks an exact distance tie, so a point on a vertex two segments share can take either segment's local code:
> - bcfishobs `sql/process.sql:163` and 7 more nearest-stream picks in the file (`ORDER BY ..., distance_to_stream`). About 2.3% of observations sit on such a tie, 1.1% where the local codes differ.
> - bcfishpass `model/01_access/sql/load_falls.sql:74`, `load_dams.sql:74` (`str.geom <-> pt.geom limit 1`).
> - bcfishpass `model/01_access/pscis/sql/02_pscis_streams_150m.sql:74` (`distance_to_stream`), and `04_pscis.sql:208`, `05_pscis_points_duplicates.sql:80` (name score, then weighted distance).
>
> The one-line fix in each: add `downstream_route_measure DESC, linear_feature_id` after the distance key. Where they compute a measure, `ST_InterpolatePoint` is already the m method.
