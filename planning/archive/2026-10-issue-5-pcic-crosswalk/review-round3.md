# Code review, round 3: extras/pcic_crosswalk (staged diff)

Scope: every staged file under `extras/pcic_crosswalk/`, read in full, plus the R1/R2 findings and
FWA_Upstream in `db/schema.sql`. I checked the diff against the checklist's general mechanisms, the
shell section and the Docker/Postgres section. The terra, sf and bcdata rules have nothing to apply
to here (bash + SQL). Every number below comes from a read-only SELECT against the local fwapg build
(36,888 placed outlets, 40.7M monthly rows). The scripts are in the session scratchpad:
`r3_tree*.sql`, `r3_side.sql`, `r3_drops.sql`, `r3_cascade.sql`, `sim06_one.sql`.

## Mechanism

**The assumption behind every R1-R3 bug: the code treats FWA's position fields as one consistent
coordinate system.** Those fields are `wscode_ltree`, `localcode_ltree`, `blue_line_key` +
`downstream_route_measure`, and the lut's `upstream_area_ha`. The code expects two things of them:

- **(a)** `FWA_Upstream` / `pcic_on_or_upstream` is a tree order on them: antisymmetric and
  transitive.
- **(b)** An ORDER BY over the same fields ranks the outlets the predicate accepts by network
  distance.

FWA_Upstream only behaves that way when four conditions hold:

1. Every local code is exactly `wscode.position`: inside its own wscode and one level deeper.
2. Local codes do not decrease going up a blue line.
3. A measure is compared only with measures on its own line.
4. A main channel and its side channel are not compared by local code, since they share a wscode.

The tributary arm (`wscode_b > localcode_a AND NOT wscode_b <@ localcode_a`) and the side-channel
arm (`wscode_b = wscode_a AND localcode_b > localcode_a`) read ltree *lexicographic* order as
*position*. Every earlier finding is one input that broke one of those conditions at one site:

| Earlier finding | Condition broken |
|---|---|
| A local code outside its wscode put outlets in a cycle | 1 |
| An out-of-order code on the Stikine put 80 tributaries above one outlet | 2 |
| Same-line pairs ordered by localcode; the side-channel arm firing on one line | 2 |
| Pairs ordered by drm across a side channel and its main line | 3 |

**The fixes patched inputs one site at a time.** None enforced the invariant once, and none asserts
it. The local-code repair in 01 was itself written under the assumption: it trusts the neighbouring
codes it copies from. So the mechanism now also reaches the repair, and through it every site that
reads repaired codes. Two of the four conditions (1 for nested codes, and 4) are not enforced
anywhere.

## Enumeration (every site: safe / not safe, why)

| # | Site | Comparison | Verdict |
|---|---|---|---|
| 1 | 00 (all) | `ST_Distance` between PCIC geometries | **Safe**: no FWA positions are compared |
| 2 | 01:42 | `c.localcode_ltree <@ c.wscode_ltree` (candidate filter) | **Not safe**: it tests the *raw* code only. The repaired code (01:98) is never re-checked, and **6 placed outlets now carry a code outside their wscode**, the condition that caused the R3 cycle. Codes nested more than one level below their wscode pass the filter (**2,397 segments, 112 placed outlets**). Findings 1 and 2 |
| 3 | 01:54-55 | run key: `row_number()` by drm within a blue line | **Safe**: measures compared within one line, and every blue line carries one wscode (measured: **0** lines with two) |
| 4 | 01:69-70 | lag/lead over runs ordered by drm | **Safe** as an ordering |
| 5 | 01:73, 79-83 | each run's code compared with its neighbours, then the neighbour's code copied in | **Not safe**: compared against *unrepaired* neighbours, and nothing checks the copied code. Finding 1 |
| 6 | 02:14 | `lfid_b = lfid_a` | **Safe**: symmetric within one segment (737 such pairs), and every same-line ORDER BY (05:41/49, 06:46, qa.sql:12) breaks the tie by drm. qa test 1 pins the segment's value |
| 7 | 02:15 | `blk_b = blk_a AND drm_b >= drm_a` | **Safe**: the outlet's drm is the point measure. Only 2 outlets sit 0.002 m past their segment's upstream measure, which hands the next segment up to the parent with the same q |
| 8 | 02:16-17 | `FWA_Upstream` when the blue lines differ | **Not safe** on three inputs: nested codes (Finding 2), invalid repaired codes (Finding 1), and the side-channel arm across lines (Finding 3) |
| 9 | 03:80-83 | score: child candidate on or upstream of x | Inherits #8 (affects candidate ranking only) |
| 10 | 03:92-95 | candidate on or upstream of its anchor | Inherits #8. Outlet 12009506 (repaired to an invalid code) no longer counts **117** placed outlets on its tributaries as above it. Placement survived only because the main-line chain carried them |
| 11 | 03:102 | `ORDER BY score DESC, candidate_rank` | **Safe**: not a position comparison |
| 12 | 04:26-29 | s on or upstream of a's anchor | Inherits #8 |
| 13 | 05:36 | `p.wscode @> c.wscode` | **Safe**: a pure prefilter that FWA_Upstream also requires; one wscode per line |
| 14 | 05:40-41 | same line: `(drm, depth, subid) <` | **Safe** |
| 15 | 05:42-46 | `FWA_Upstream` for the FWA parent | Inherits #8. **14 outlets on 7 tributaries** are parented through nested codes (7.03 m³/s). Finding 2 |
| 16 | 05:49 | `ORDER BY same-line, nlevel DESC, drm DESC, …` | The same-line key is **safe**, and `nlevel DESC` is safe given a tree predicate. Comparing drm across lines at equal nlevel is the **accepted residual**: in 220 pairs the predicate calls a side-channel outlet nearer and the ORDER BY takes the main-channel one. For the 7 largest children, 5 tributary mouths touch the main channel (geometry checked), so there the ORDER BY corrects a predicate error. Not reported |
| 17 | 05:61-80 | local area = A(outlet) - sum A(FWA children), lut upstream area used as a position | **Not safe** (documented in code, not in the README): **801 negative, 1,519 zero**. Finding 5 |
| 18 | 05:117-131, 141-144 | FWA tree depth + reachability guard | **Safe**: raises on a cycle |
| 19 | 06:28, 32, 40 | segments use repaired codes | Inherits #5 |
| 20 | 06:36-41 | owner: outlet on or below the segment | Inherits #8: the side-channel arm, nested codes and invalid codes. Findings 2 and 3 |
| 21 | 06:46 | owner ORDER BY | Mirrors 05:49; same verdict as #16 |
| 22 | 06:53-58 | share by area | Same as #17 |
| 23 | 06:64-67 | children of the owner on or upstream of the *segment* (the segment is `a`, so its own local code drives the tributary arm) | **Not safe**: this is where the defects reach the output. Findings 1, 2 and 3 |
| 24 | qa.sql:12 | `ORDER BY drm DESC` within one lfid | **Safe** |
| 25 | qa.sql:54-69 | `lead()` by drm per blue line | The ordering is **safe**, but it covers 3 named lines and none of the defects below reach them. Finding 4 |
| 26 | qa_gauge.sh:47, 50 | `FWA_IndexPoint` within 500 m, ordered by area ratio, then distance | **Safe**: no code comparison |

**The predicate is not a tree order.** For every placed outlet c with FWA parent p, I counted the
placed outlets q that are below c but not below p. There are 1,906 such (c, q) pairs, and every one
falls into one of three classes:

- 737 are same-segment pairs (#6, harmless).
- 1,106 involve a main channel and its side channel (#16 residual, and Finding 3).
- 63 involve a nested local code (Finding 2).

No other cause remains.

## Findings

- **[bug] sql/pcic_crosswalk01_candidates.sql:46-83: the local-code repair copies codes it has
  itself judged out of order, and writes codes outside the segment's wscode.**
  - **How.** Each run is compared with its *unrepaired* neighbours (`lag`/`lead` of the raw codes),
    and `coalesce(n.below, n.above)` copies a neighbour's raw code with no check that it is valid.
    So when a spike run is repaired down, the valid run just above it now sits below the spike's
    raw code, reads as a "dip", and takes the spike's bad code. The bad code moves up one run
    instead of going away.
  - **Example.** INKR, blue line 360885169:
    - drm 81754-82098 carries `700.998191.999667.002972`, repaired to `.988947`.
    - drm 82098-82576 carries a valid `.993741`, repaired *to* `.999667.002972`.
  - **Measured** (replicating 01's run logic read-only):
    - **3,712 of 7,130 repaired runs (8,781 of 14,326 segments, ~1,700 blue lines)** copy their
      new code from a run the same rule judged out of order.
    - **3,436** of those runs had a valid code (inside their wscode, one level deep) and were
      overwritten with a bad one.
    - **297** repaired codes lie outside the segment's wscode; 296 of them were valid before the
      repair.
    - **1,222** repaired codes are nested more than one level deep.
    - **6 placed outlets** carry an outside-wscode code (2007255, 2007326, 9000064, 12007190,
      12009506, 206006865). That is exactly the condition that caused the R3 cycle. Blue line
      354135696 had its *mouth* run (code = wscode) "repaired" to `930.055749.008372`.
    - After repair, **1,134 decreases remain on 697 blue lines**; there were 3,586 on 1,696 before.
  - **Effect in the built table.** At a cascade-repaired segment, the tributary arm drops tributaries
    that join below it from "above" (06:64-67):
    - INKR main line: segment 69062305 carries **0.07 m³/s** between 34.9 above and the same below.
    - BELA blue line 360885253 drops **78.8 → 30.1** on segment 9016772.
    - Main lines (`blue_line_key = watershed_key`) have 49 pairs where flow halves going downstream
      (q > 1). 14 of them sit at repaired codes.
  - **False claims.** The 01 header ("carries the local code of the run below it, so it compares
    with tributaries as its neighbours do") and README:42-45 are false for those 3,712 runs.
  - **Fix.**
    - Clean codes first: treat a code not `<@ wscode` as absent, and truncate nested codes (Finding
      2).
    - Then decide out-of-order runs against neighbours that are already clean and repaired: iterate
      to a fixpoint, or fit a non-decreasing sequence. Never copy a code that is invalid.
    - Then `RAISE` in 01 unless every code is `<@ wscode` at `nlevel(wscode)+1` and non-decreasing
      by drm along each blue line. That is the invariant the header states, and nothing executes it
      today.

- **[bug] sql/pcic_crosswalk01_candidates.sql:42 and sql/pcic_crosswalk02_prepare.sql:16-17
  (reaching 05:42-46 and 06:36-41, 64-67): a local code nested more than one level below its wscode
  makes FWA_Upstream place a whole sub-basin on the wrong side of an outlet.**
  - **How.** A Fraser segment at drm 1171085 has localcode `100.832081.005180`, the code of a side
    channel of tributary 100.832081 that enters the Fraser directly. It is in order and inside its
    wscode, so neither the 01 filter nor the repair touches it.
  - The tributary arm then calls every stream `100.832081.k` with k > 005180 "upstream" of that
    point. Those streams drain into 100.832081, which joins the Fraser *below* it, at 1170913. The
    tributary's own main stem (`100.832081` sorts below `100.832081.005180`) is not called upstream,
    so one tributary basin is split across the outlet.
  - **Measured.**
    - 2,397 such segments on 850 blue lines; 112 placed outlets sit on them.
    - **14 outlets on 7 tributaries** take a nested-code outlet as their FWA parent (05), 7.03 m³/s
      in total.
    - Trib `100.190442.998192.288800` (blue line 356347677, 28 km) carries **0.10-0.42 m³/s** along
      its main stem. Sub-tributaries 3003637 (1.38), 3003633 (0.79) and 3003594 (0.30 m³/s) join
      it, but all three are parented to 3003617 on the river it drains into.
    - The INKR segment in Finding 1 carries a nested code that the repair copied.
  - **Fix.** Use `subpath(localcode, 0, nlevel(wscode)+1)` for every position comparison:
    candidates, crosswalk rows and 06 segments. The segment then sits just above confluence X.y, and
    all of X.y's basin falls on one side.
  - **Expect placement to move.** 3003617 is the PCIC anchor of those three outlets, so they become
    `broken_chain` or trigger a demotion. Measure the placed count after the change.

- **[bug] sql/pcic_crosswalk06_segments.sql:36-41, 64-67 (via 02:16-17): side-channel segments get
  either the whole river's flow or zero, decided by a local-code tie.**
  - **How.** For a segment on a side channel (`blue_line_key != watershed_key`), owner and children
    are decided by FWA_Upstream's side-channel arm, which compares local codes *across* blue lines.
    The R2 fix removed that arm only for the same line.
  - A main-line child whose local code is strictly greater than the segment's counts as above it,
    so the segment gets the full main-stem `q_acc`. An equal code fails the strict `>`, and the
    segment gets `q_local × share`, usually 0.
  - **Example, from a read-only replica of 06.** Fraser side channel 355992048 (HARR):
    - Segment 701346600 (lc `100.077115`) carries **3,055.8 m³/s**: its owner is 4009484 and both
      children are above it.
    - The next segment down, 701346838 (lc `100.076435`, equal to child 4009484's code), carries
      **0**, as do all 11 segments to the mouth.
  - **Measured.**
    - Of 67,917 side-channel segments in the output, 26,974 carry ≥ 10 m³/s and 2,956 carry 0.
    - **717 side channels** have a step where flow halves going downstream with q > 10 (one step on
      each). The drops sum to ~160,000 m³/s.
    - Main lines have 9 such steps.
  - **Fix.** Choose one rule and apply it explicitly. Either compare a side-channel segment through
    the main-channel position it rejoins, or emit no flow on side channels and say so in the README.
    Do not leave it to the side-channel arm.

- **[fragile] sql/qa.sql:54-69: no QA test can fail on any of the three bugs above.**
  - The monotonicity test reads 3 named blue lines, and none of the measured defects is on them.
  - Over every main line (`blue_line_key = watershed_key`), 32 consecutive pairs with q > 10 drop
    by more than 10% going downstream (27 lines). Side channels add 718.
  - Add these checks:
    - The code invariant from Finding 1, as a `RAISE` in 01.
    - The monotonicity test over all main lines, with a count ceiling.
    - A side-channel bound: q on a side channel at most q on its main line.

- **[fragile] sql/pcic_crosswalk05_subbasins.sql:61-80, sql/pcic_crosswalk06_segments.sql:53-58:
  2,320 sub-basins (6%) have local area ≤ 0, so their local runoff reaches no interior segment.**
  - The lut maps a tributary-mouth segment to the polygon of the stream it joins. Example: 12007188
  (trib mouth) and 12007190 both map to watershed 7707411 (25,298 ha), and parent 12007178 gets
  local area -24,746 ha.
  - **Size.** 801 sub-basins are negative and 1,519 zero. They hold **1,734 of 21,448 m³/s** (8%) of
    all local runoff. On their interior segments, share is 0 and that runoff is missing; it appears
    only at and below the outlet.
  - The SQL comments acknowledge `A_local <= 0`. The README caveats do not, and say runoff "is spread
    over that sub-basin by area".
  - The same lut mapping makes flow step non-monotonically within a sub-basin. On 360845804, drm
    2537 maps to 7707411 and carries 7.89 m³/s, between 3.36 above and 3.36 below.
  - **Fix.** Either fix the area source (use the segment's own upstream area in place of the
    confluence polygon), or document the gap and its size.

## Checked and fine

- **R2 same-line fixes.** The function's measure-only arm and the same-line-first ORDER BYs in
  05/06/qa are in place and consistent. The FWA parent relation reaches every placed outlet
  (cycle guard passes).
- **Shell.**
  - `-q` on the demote count; `-L`, `-m 1800` and 255-on-failure in `fetch_batch`.
  - QA gate: a NULL result and a missing line both fail.
  - A failed group in the `xargs` over 06 exits 123, which stops the script under `set -e`.
- **Same-segment ties.** The lfid-equality arm and its 737 symmetric pairs, together with outlets
  at segment ends (2 of them, 0.002 m), produce no measurable error.
- **`set -x` printing `DATABASE_URL`.** It matches `extras/discharge`, so not flagged (accepted
  convention).
