## Outcome

The review of smnorris/fwapg#201 asked for one tie rule across point matching, plus the smnorris/fwapg#86 filters and the smnorris/fwapg#161 z. The migration on the upstream branch `indexpoint-tiebreak` was reworked as commit `a8d00b9` on top of the #39 tie-break `d955688`, and cherry-picked here.

`FWA_IndexPoint` keeps the tie-break and takes the point and measure from the stream geometry: `ST_LineInterpolatePoint` at the fraction of the closest point gives a PointZM, and the measure is its m. It gains `include_disconnected` and `include_null_localcodes`, applied before the per-stream pick and defaulting to today's rows, and a point on a watershed-group boundary no longer errors. `extras/channel_width` calls it in place of its own copy of the pick.

The m measure exposed something no gate had seen. At a stream's head it equals the top segment's `upstream_route_measure`, and every function that takes a measure decided validity with its own hand-copied predicate. So the user made two more decisions mid-run. Decision 5 gave `FWA_LocateAlong` the `FWA_WatershedAtMeasure` rule. Decision 6 extended it to the traces and watershed functions: the highest segment whose range, closed at the top, holds the measure. `FWA_UpstreamBorderCrossings` and `FWA_SliceWatershedAtPoint` also get their slice fractions clamped. The migration now covers 14 functions.

The user asked for tests of every premise. There are 56 cases across five files, and each of 15 one-change reverts turns at least one red. Code-check ran three rounds and ended on a mechanical enumeration of the measure consumers. Nothing has been posted upstream. Durable findings: `research/fwa_position_codes.md`, the sections "Measures that name the same point disagree, by field" and "A stream's head is outside `[downstream, upstream)`".

## Measurement

All on the loaded provincial fwapg; functions compared as scratch copies, and tests run in a transaction that rolled back. Details in `findings.md`.

- **Measure, formula against geometry m:** at most 3.0 mm apart (median 0.02–0.13 mm) on 11,190 indexed rows, and 4.6 mm on FISS sites. `ST_LineMerge` dropped m (PostGIS 3.5.2, GEOS 3.9.0). Default flags changed no stream and no segment.
- **`FWA_WatershedAtMeasure`'s point step:** misses 156 → 0 of 1,190 random-point rows; 230 → 0 and 929 → 0 on the other two sets.
- **`FWA_LocateAlong`:** misses 1,627 → 34 of 11,182 indexed measures. The 34 left are the 4 dp band where one segment overlaps the next by under 0.05 mm. It never lost or moved a point the old rule found.
- **Stream heads:** end m equals `upstream_route_measure` at 1,616,885 of 1,783,289 blue lines (90.7%), so a strict upper bound rejected about 95% of m-measures at heads, against about 50% of formula measures. The 16 consumers with that bound or a `length_metre` fraction were found by a sweep of the function sources. 12 are fixed; the other 4 (interval functions) take integer measures they generate. On 558 measures, every trace and watershed result that returned rows before is unchanged. Heads gained: watershed stream 300 of 300, downstream trace 224.
- **Filters:** on 48,716 PCIC outlets (150 m, 5 streams) the filtered call matches an independent query exactly (92,606 rows). It recovers 727 streams that filtering afterwards drops.
- **channel_width:** 63,413 → 63,501 FISS sites matched, 37 s → 105 s. The 88 gained sites are rows the old code dropped when `ST_LocateAlong` at the formula measure came back empty. Of the 14 that changed stream, 8 come from the wider search window and 6 are exact ties.
- **Wrong turns:**
  - The first measure change made `FWA_LocateAlong` misses rise (the stream-head case), which went to the user.
  - A `count(*)` probe "showed" MultiPoint input working. The inlined function never computed the column. The plan review had it right.
  - Pinning a segment id from unrounded coordinates broke the filter test.
  - The first decision-6 build dropped the upper bound outright, which let the traces answer 49 m past a table's last segment.
  - The revert builder once stopped part-way and left stale files that then ran. Those results were discarded.
  - A comparison ran out of memory on `string_agg` of whole traces.
  - My stated "past the head finds no point" claim was false for the traces until the top was closed.

## Evidence

Ad hoc SQL, the harness and the reverts were in the session scratchpad and are not committed. The scratch schema was dropped. The record is `findings.md` and `review-*.md` here.

## Owed

- ~~Push `indexpoint-tiebreak`, edit the #201 body, post the reply and the bcfishobs/bcfishpass notes~~ done 2026-10-30: `indexpoint-tiebreak` fast-forwarded d955688 → a8d00b9, #201 title and body replaced, one comment posted (smnorris/fwapg#201, issuecomment-6530373831). Texts as posted are in `drafts.md`; Simon will review in November
- Re-apply the fwa_indexpoint grants on our deployment after the migration (DROP resets them), and restart pg_featureserv
- Open issues for the NGE picks still on the formula measure: this fork's `pcic_crosswalk02_candidates.sql` (`ST_LineMerge` and formula) and fresh's `frs_point_snap()` (review S1) (2026-10-26: fresh#266 widened, wet#127 and link#383 filed for the package side; the PCIC crosswalk is still open)
- After upstream settles: merge the newgraph PR, close #39 and #41 by hand naming the PRs, then migrate the local fwapg (`cd db && DATABASE_URL=... ./migrate.sh`) **when you say so**

Drafts for the first two are in `drafts.md`.

Closed by: commit 4121331 (cherry-pick of upstream a8d00b9) / PR into newgraph from `41-fwa-indexpoint-one-tie-rule-and-measure`
