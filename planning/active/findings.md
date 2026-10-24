# Findings — fwa_indexpoint(): an exact distance tie on one stream is broken by row order (#39)

## Issue context

See the issue body (#39). In short: `DISTINCT ON (blue_line_key) ... ORDER BY blue_line_key,
distance_to_stream` in `whse_basemapping.fwa_indexpoint()` does not decide between two segments of
one stream that are exactly equidistant from the point, and the outer `ORDER BY distance_to_stream`
can tie the same way at the `LIMIT`. Found from wet's gauge snapping (08EC013, 08KD006).

## Both gauge ties are tributary junctions (2026-10-24, local loaded fwapg)

| gauge | blue_line_key | downstream seg (ds–us) | upstream seg (ds–us) |
|---|---|---|---|
| 08EC013 | 360886970 | 5086038 (96824.659–97410.075), lc …367117 | 5086970 (97410.075–98794.764), lc …369337 |
| 08KD006 | 356360570 | 703862843 (13543.875–14040.005), lc …061391 | 703862887 (14040.006–14162.330), lc …063640 |

The localcodes differ because a tributary joins at the shared vertex. fwapg resolves a measure as
`[downstream, upstream)` (`downstream_route_measure <= m AND upstream_route_measure > m`, e.g.
`schema.sql:1720`, `:2565`, `fwa_locatealong` `:2478-2480`), so a measure on the vertex belongs to
the upstream segment. `extras/pcic_crosswalk/sql/pcic_crosswalk02_candidates.sql` (newgraph only)
already breaks this tie that way. **Decision at the gate: the upstream segment wins** (the issue had
proposed the lowest id, which would have picked the downstream one in both cases).

## The old answer depends on the plan, and can be unlocatable

- With index and bitmap scans off, the old function returns 5086038 for 08EC013 instead of
  5086970 (real table). On temp copies of the nearby segments (asc and desc physical order), turning
  scans off flipped both gauges. Physical order alone, with the same plan, did not flip them. The new
  body returned the upstream segment in all eight runs.
- On 08KD006 the old function returns 703862843 with measure 14040.005812552621
  (`downstream_route_measure + length_metre`). That is below the next segment's start
  (14040.0058125527) and above its own stored `upstream_route_measure` (14040.004934962686), so
  `fwa_locatealong(356360570, 14040.005812552621)` returns 0 rows. The new body returns the upstream
  segment at ST_LineLocatePoint 0, so the measure is its `downstream_route_measure` exactly. (Found
  by the plan review.)

## Ties are common: old vs new on 1,242 points (num_features 5, transaction rolled back)

| points | n | segment changed, same streams | stream set changed | order changed |
|---|---|---|---|---|
| random, one per watershed group sampled | 242 | 9 | 0 | 0 |
| within ~100 m of a random segment's start | 1,000 | 57 | 0 | 1 |

All 66 changed segments were exact float ties, and in all 66 the new segment is the upstream one.
65 of the 66 were adjacent. Localcode differed in 32 and wscode in 0. The measure moved at most
3.5e-9 m. In 44 of the 66, the old `linear_feature_id` named the downstream segment while its measure
fell on the upstream one. The one order change is two streams tied at 40.259 m after rounding: the
new outer sort on the unrounded `b.distance_to_stream` puts the truly nearer one first.

These counts are a floor on how often ties occur. They miss ties where the old plan happened to pick
the upstream segment.

## Downstream of fwapg: bcfishpass and bcfishobs

- Neither calls `fwa_indexpoint`: 0 hits on bcfishpass `origin/main` (620dbe4, one commit behind
  smnorris main) and on bcfishobs `origin/master` (identical to smnorris main), and 0 in a GitHub
  code search of both smnorris repos. **This change cannot alter their outputs.** Crossing ids come
  from road and rail intersections, and PSCIS ids are `stream_crossing_id`.
- Both carry their own copy of the same pattern, with the same unbroken tie:
  - bcfishobs `sql/process.sql:157-163`: `distinct on (observation_key, blue_line_key) ... order by
    observation_key, blue_line_key, distance_to_stream`. Its insert then joins the candidates back
    on `distance_to_stream` (`:178-181`), so on a tie both segments come through. The later
    `DISTINCT ON (observation_key) ... ORDER BY observation_key, downstream_route_measure` cannot
    separate them, because both carry the measure of the segment the first pick chose.
  - bcfishpass `model/01_access/pscis/sql/02_pscis_streams_150m.sql:60-74` (and `:228-237`).
- Stored bcfishobs observations (375,962) on the local DB: 0 have a measure outside their
  `linear_feature_id`'s segment (±1 mm, a tolerance that cannot see a vertex tie), and 588 have a
  stored localcode different from their segment's, 5 of them at the segment's top.
- **Exact same-stream ties in bcfishobs's own snap.** For each observation, I counted whether
  another segment of its stored `blue_line_key` is exactly as far from the source point
  (`whse_fish.fiss_fish_obsrvtn_pnt_sp`) as its stored segment. Seeded sample of 5,000 (setseed
  0.39):

  | match type | obs | exact tie | tie, localcodes differ |
  |---|---|---|---|
  | A. stream, within 100 m, lookup | 2,461 | 46 | 28 |
  | B. stream, within 100 m, closest | 315 | 5 | 2 |
  | C. stream, 100–500 m, lookup | 495 | 9 | 5 |
  | D. waterbody, lookup | 1,483 | 54 | 32 |
  | E. waterbody, closest | 246 | 7 | 1 |
  | all | 5,000 | 121 (2.4%, 95% CI 2.0–2.9%) | 68 (1.4%, CI 1.0–1.7%) |

  Scaled to 375,962 observations, that is about 7,500–10,700 on a tie whose segment depends on row
  order, and 3,900–6,300 where the two segments' localcodes differ (a tributary junction). At such
  a junction the localcode decides whether bcfishpass's upstream/downstream joins count the
  observation on the tributary's side. The full-population count is below once measured; the
  first attempt over all rows timed out at 30 min on a slow plan, while the sample took 13 s.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `sed` `\(…\)\?` did not match on macOS, so the temp-function rename failed with "already exists" | `sed -E` with `( …)?` |
| `array_agg` with no `ORDER BY` made 241/242 points look reordered | `WITH ORDINALITY` on the lateral call, aggregate by ordinality |
