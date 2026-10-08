# Code review, round 2: extras/pcic_crosswalk (staged diff)

Scope: every staged file under `extras/pcic_crosswalk/`, checked against the full code-check
checklist, plus the eight round-1 fixes. SQL findings were measured read-only against the local
fwapg DB: the current `whse_basemapping.pcic_fwa_crosswalk`, the `fwapg.pcic_*` staging tables,
and the `fwa_stream_networks_discharge_monthly` build in progress (96 watershed groups done). I
reproduced 06 for single reaches with a read-only SELECT
(`scratchpad/sim06.sql`), and the built table agrees with it on the reach that is already done.

## Findings

- **[bug] sql/pcic_crosswalk05_subbasins.sql:40, sql/pcic_crosswalk06_segments.sql:35-42 and 60-63,
  sql/pcic_crosswalk02_prepare.sql:13**: on the same blue line, "nearest outlet below" and "on or
  upstream" are decided with `localcode_ltree`, which is not monotone along a blue line. The result
  is nested outlets counted two or three times over.
  - **The ordering.** Both 05 and 06 sort by `nlevel(wscode) DESC, localcode DESC, drm DESC`.
    FWA local codes do not increase upstream along a blue line. Example, Fraser
    (`356364114`): the outlet at drm 103982 has localcode `100.076435`, and the one at 107577 has
    `100.076034`. Example, `360884039` (OWIK): localcodes run `…704175.004367.021476` (drm 42655),
    `…704175.004367` (44622), `…704175` (47975), and an ltree prefix sorts lower.
  - **The predicate.** `pcic_on_or_upstream` ORs in `FWA_Upstream`, and FWA_Upstream's
    side-channel arm (`wscode_b = wscode_a AND localcode_b > localcode_a`, schema.sql:3331)
    applies even when `blue_line_key_a = blue_line_key_b`. So it reports a downstream outlet on the
    same line as upstream. The review brief describes the same-line case as "requires
    b.drm >= a.drm + tolerance". That is incomplete: this arm does not check the blue line.
  - **Measured:**
    - 272 placed outlets have a `fwa_parent_subid` that skips a nearer placed outlet on the same
      blue line.
    - 501 same-line pairs where FWA_Upstream calls the downstream outlet upstream, on 72 blue
      lines. These include the Fraser (HARR), the Stikine (`360886273`, 164 pairs) and the Skeena.
    - 637 sub-basins still have `local_area_ha < 0`. This contradicts the README line 48 claim
      that the outlets directly above a sub-basin "never overlap".
  - **Effect, in the built table:**
    - Fraser drm 103908 to 107369 carries **6111 m³/s against PCIC's 3056**. Outlet 4000197 has
      `q_in` 6111, because 4000182 is counted both directly and inside 4009484.
    - OWIK `360884039` (reproduced, not yet built): 8000460 takes 8000474, 8000494 and 8000492 as
      direct children, although they are nested along the line. Its reach carries **59 m³/s
      against PCIC's 21.5 to 22.6**. Outlets 8000474 and 8000494 own no segments, not even their
      own. Segments above 8000474 still list it in `upstream_subids`.
  - **Fix:**
    - In `pcic_on_or_upstream`, use only the measure when the blue lines match:
      `lfid_b = lfid_a OR (blk_b = blk_a AND drm_b >= drm_a) OR (blk_b <> blk_a AND FWA_Upstream(...))`.
      03 and 04 share this function.
    - In 05 and 06, order on the same stream by measure, not by localcode
      (`nlevel(wscode) DESC, drm DESC, depth DESC, subid DESC`). The same order belongs in
      qa.sql:13.

- **[bug] sql/pcic_crosswalk05_subbasins.sql:18-42, 74-87, and sql/pcic_crosswalk06_segments.sql
  (round-1 fix 3)**: collecting flow by FWA nesting pairs FWA areas with PCIC outflows that do not
  nest the same way, so mainstem flow collapses below a misplaced small sibling.
  - Fix 3 made the children's areas disjoint. But `Q_out` of an outlet is PCIC's, so when PCIC
    sibling c sits FWA-above sibling p, `Q(p)` does not contain `Q(c)`.
  - At p's own segment the flow is `max(Q(p), Q(c) + …)`, because `q_local` is clamped to 0.
  - The segments just below p belong to p's anchor, whose `upstream_subids` list p but not c. Their
    flow is `Q(p) + share × q_local(anchor)`, so c's flow vanishes and only reappears in full at
    the anchor.
  - This is the round-1 symptom ("flow drops out there and comes back below"), moved rather than
    removed.
  - **Measured**, excluding the ordering cases above:
    - 781 placed outlets have `fwa_parent_subid` ≠ `anchor_subid`.
    - In 368 of them the child's PCIC flow exceeds its FWA parent's.
    - In 205 of them the child's flow is more than twice the parent's and above 10 m³/s.
  - **Effect, in the built table:** the Fraser at drm 94096 to 95853 carries **501 m³/s between
    3062 above and 3062 below**. Outlet 4000218 (Q ≈ 0, a PCIC sibling of mainstem outlet
    4000217) is placed on the Fraser below 4000217. Similarly, 4000204 (Q 75) sits under 4000203
    (Q 3063).
  - **Across the 96 groups built so far:** 616 consecutive segment pairs above 10 m³/s where flow
    halves going downstream, on 564 blue lines. Both findings feed that count.
  - **Fix:** treat "FWA parent is not a PCIC ancestor" as a placement inconsistency. Unplace or
    demote the smaller sibling, as in 04, and re-run placement until stable. Do not reconcile it in
    05/06.

- **[fragile] sql/qa.sql:15-23, 40-54**: the QA gate (round-1 fix 6) cannot fail on either defect
  above.
  - The mass-balance test drops every month with `q_out < q_in`, and that is exactly the
    signature of both bugs: 405 sub-basins have annual `q_in > 1.5 × q_out`, and 318 have
    `q_in > 2 × q_out`.
  - The mainstem test allows 5% of segment pairs to drop, and a few kilometres of a 2× or 1/6
    error on the Fraser is far below that.
  - A test that would fire is the count (or flow-weighted share) of sub-basins with `q_in` well
    above `q_out`, bounded by an absolute ceiling.

- **[fragile, minor] qa_gauge.sh:7-8, 35**: a station with a null `DRAINAGE_AREA_GROSS` interpolates
  `null` into `ORDER BY abs(ln(... / null))`. Every candidate then sorts as NULL, and `LIMIT 1`
  picks an arbitrary stream among 5 within 500 m, which is worse than the old nearest-stream snap.
  The output shows `gauge_area_km2` as NULL but gives no warning. An unknown station number also
  prints zero rows and exits 0. Add `c.distance_to_stream` as a secondary sort key, and refuse when
  `LON` or `AREA` is `null`.

## Round-1 fixes checked and fine

- **Fix 1.** `psql -q -tXA` drops the command tag; measured: `SET` was printed without `-q`
  and not with it. The loop breaks when `n` is 0 and exits 1 if round 10 still demotes.
- **Fix 2.** Every reduction step is chained and returns 255. The awk `END` check runs after an
  `exit` in the main rule. The local cache holds no poisoned batches now: 28 zero-byte CSVs, all
  single-outlet and all in `missing.txt`. 584,256 monthly rows = 48,688 outlets × 12.
- **Fix 3.** Area overlap through the PCIC anchor is gone, but see the two bugs above.
- **Fix 4.** `no_series` outlets: 28, none placed.
- **Fix 5.** A lut row is required in 01. 0 placed outlets lack a
  `fwa_watersheds_upstream_area` row, and the lut is unique on `linear_feature_id`.
- **Fix 6.** The QA output format is `name|t`, with no blank lines between result sets. A NULL
  prints `name|`, and a query error aborts through `ON_ERROR_STOP` and `set -e`.
- **Fix 7.** `-L` is added. Halving on a non-422 failure stops at 50 or fewer outlets with 255,
  and xargs stops on 255.
