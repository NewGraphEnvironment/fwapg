# Code review, round 4: extras/pcic_crosswalk (staged diff)

Scope: every staged file under `extras/pcic_crosswalk/`, read in full, and the two added lines in
`extras/README.md`. I read rounds 1-3 and checked the checklist's general mechanisms, its shell section
and its Docker/Postgres section against the diff. The checklist's psql rules hold here: no `:var` sits
inside a `$$` body, and a failing psql stops the run under `set -e` and `ON_ERROR_STOP`. I tested the
path table against the local build with read-only SELECTs (session temp tables only). The scripts are in
the session scratchpad, `r4/junc*.sql`.

## Mechanism, one axis over

Round 3 found that the code read FWA codes as positions. The fix drops local-code ordering, which was
the right call, but it builds the path table on a new assumption:

> **A blue line's mouth lies on its parent.** The parent is the main line of its parent wscode, or
> the `watershed_key` line for a side channel. The point on the parent nearest the mouth is then
> where its water enters the parent.

The equality junction (`localcode = wscode`) holds up. Wherever the mouth actually lies on the parent,
the equality junction is within 10 m of it on all but 104 of ~1.47 M lines, and none of those 104 has
a placed outlet in the gap.

The geometric fallback (`ORDER BY s.geom <-> p.mouth LIMIT 1`, with no distance bound) is where the
assumption breaks. It projects the mouth onto the parent wherever the parent happens to be nearest,
even when the mouth reaches the parent through a side channel or a reservoir flowline, or leaves BC
and reaches it outside the FWA. Most measured distances between mouth and parent:

| Class | Lines | Mouth > 100 m from parent | Mouth > 1 km from parent |
|---|---|---|---|
| Main stems with no equality match (geometric) | 14,693 | 12,354 | 4,101 |
| Side channels (always geometric) | 74,430 | 18,765 | 1,543 |
| Main stems with an equality match | 1,482,199 | 7,423 (mouth touches a side channel of the parent, 7,109) | 181 |

## Enumeration (every site: safe / not safe, why)

| # | Site | Comparison | Verdict |
|---|---|---|---|
| 1 | 00:42-71 | `ST_Distance` among PCIC features | **Safe**: no FWA positions |
| 2 | 01_paths:23-34 | `DISTINCT ON (blue_line_key) ORDER BY drm` takes wscode, watershed_key and mouth from the lowest non-6010 segment | Ordering **safe**: measured **0** lines with more than one wscode or watershed_key. Using that segment's start as "where the line meets its parent" is **not safe**: on a line that leaves BC it is the border crossing (Finding 1) |
| 3 | 01_paths:38-43 | `mains`: `DISTINCT ON (wscode) ORDER BY blk` | **Safe**: one wscode in BC has two main lines |
| 4 | 01_paths:49-52, 57-59 | parent = watershed_key (side channel), or the main of `subpath(wscode, 0, n-1)` | Safe as a key. Not safe as "the line the water enters" when the mouth does not touch that line (Finding 1). 26,095 sea-draining lines get no path (correct). 6 more have a parent wscode carried only by 6010 or side segments; they have 0 placed outlets on or above them (negligible) |
| 5 | 01_paths:66-72 | junction = `min(drm)` of parent segments with `localcode = wscode` | **Safe where the mouth meets the parent**. Only 36 lines are off by > 100 m, with 0 placed outlets between the junctions; out-of-order duplicates do not bite. Where the mouth meets a side channel of the parent (7,109 lines), the code marks FWA's projected position, not where the water enters: 2,428 are > 100 m off the side channel's own junction, and 18 outlets on 26 lines read FWA-high. That is a residual of Finding 1 |
| 6 | 01_paths:73-79 | geometric fallback: nearest parent segment to the mouth, `drm + ST_LineLocatePoint * length_metre` | Units and direction are **safe**: `length_metre` matches `urm - drm` within 1 m on all but 3 of 4.9 M segments, and FWA digitizes from the downstream end. **No distance bound: not safe.** Finding 1 |
| 7 | 01_paths:92-112 | recursive walk, cycle stop, `DISTINCT ON … cardinality DESC` | **Safe**: each line has one parent row (PK), so each walk is a chain, and the longest row is the full path. **0** truncated paths (no path ends at a line that still has a parent). The cycle stop truncates silently. That is harmless today, but it becomes a real risk once the paths follow touched lines (Finding 1 fix) |
| 8 | 01_paths:124 | function: same line, `drm_b >= drm_a` | **Safe**: one line |
| 9 | 01_paths:125-132 | function: a's line on b's path with junction `>= drm_a` | Logic **safe**. It inherits the junction values from #5 and #6 |
| 10 | 02:22, 28-51 | rank by distance; `DISTINCT ON (blk) ORDER BY distance` | **Safe**: not a position comparison. Filters are applied before the per-line pick, as intended |
| 11 | 02:32 | candidate drm = `drm + fraction * length_metre` | **Safe**: 1 placed outlet lies outside its segment, by about 0.002 m |
| 12 | 03:8-18 | PCIC subtree sizes | **Safe**: PCIC tree only |
| 13 | 04:60-62 | anchor = parent or parent's anchor | **Safe**: PCIC tree |
| 14 | 04:77, 86 | score and anchor test via `pcic_on_or_upstream` | Inherits #9 |
| 15 | 04:93 | `ORDER BY score DESC, candidate_rank` | **Safe**: not a position comparison |
| 16 | 05:12-18, 26 | demotion test via the function | Inherits #9 |
| 17 | 06:38-41 | `seg_measure` from the outlet's own segment | **Safe** |
| 18 | 06:58-63 | step 0: `(seg_measure, drm, depth, subid) <` on one line | **Safe**: one line. 161 outlets sit exactly on a segment start, and the tuple groups each with its own segment |
| 19 | 06:64 | step i: `o.drm <= junction` | **Safe** given correct junctions. Inherits #6: e.g. Okanagan outlet 6003150 is parented to Columbia outlet 5024140 |
| 20 | 06:66 | `ORDER BY step, seg_measure DESC, drm DESC, depth DESC, subid DESC` | **Safe**: `o.blue_line_key = st.blk`, and a line occurs once per path, so measures are only ever compared within one line at one step. **No drm comparison across lines remains** |
| 21 | 06:73-97 | local area = A(outlet) − Σ A(FWA children) | Accepted lut limitation (documented) |
| 22 | 06:105-124 | PCIC local runoff → placed outlet or anchor | **Safe**: PCIC tree. A child with no series is correctly not subtracted |
| 23 | 06:134-176 | FWA depth, reachability guard, level-by-level accumulation | **Safe**: raises on a cycle |
| 24 | 07:26-30 | `seg_measure` | **Safe** |
| 25 | 07:65-70 | owner: step 0 `o.seg_measure <= s.drm`, step i `o.drm <= junction`; same ORDER BY as 06 | **Safe**, and it is the same rule as 06:58-66 (one fact derived once). Inherits #6 |
| 26 | 07:91-97 | children above a segment: same line by `seg_measure >= s.drm`; other lines via the function at `s.drm` | **Safe**: a junction inside the segment counts as above it, which matches the segment taking its uppermost outlet's q. Inherits #6 |
| 27 | 07:101-118 | `ON CONFLICT DO NOTHING` | **Safe**: the lut is 1:1 (4,538,224 rows, 4,538,224 lfids), so nothing is masked |
| 28 | qa.sql:8-13 | `DISTINCT ON (lfid) ORDER BY drm DESC, depth DESC, subid DESC` | **Safe**: same segment, same tie order as 07 |
| 29 | qa.sql:24-37 | accumulated vs PCIC | Not a position comparison. **Cannot fail on Finding 1** (Finding 2) |
| 30 | qa.sql:56-70 | `lead()` by drm per blue line | **Safe**: one line. It sees drops only, while Finding 1 is a step *up* at the wrong place (Finding 2) |
| 31 | qa_gauge.sh:47-51 | `FWA_IndexPoint` 500 m, `ORDER BY abs(ln(area ratio)), distance` | **Safe**: a match score between candidate lines, not a position |

Everything not marked "not safe" or "inherits" stands on its own. Every inherited site resolves to one
cause, #4/#6 (Finding 1).

## Findings

- **[bug] sql/pcic_crosswalk01_paths.sql:73-79 (also 29, 49-52): the geometric junction projects a
  line's mouth onto its wscode parent with no distance bound, so tributaries that reach the parent
  elsewhere (outside BC, or through a side channel or reservoir flowline) add their flow to the parent
  at an invented point, up to 110 km away.**
  - **How.** The parent comes from the wscode prefix, or from `watershed_key`. When the parent has no
    segment with `localcode = wscode`, the junction is the point on the parent nearest the mouth.
    Nothing checks that the mouth is anywhere near the parent. The header ("where its mouth meets the
    parent's geometry", 01:15) and README:48-50 describe a meeting point that does not exist for these
    lines.
  - **Streams that leave BC.** 19 lines with placed flow have a mouth on the BC boundary that touches
    nothing. 17 of them are main stems, carrying **242 m³/s** into BC rivers at made-up junctions.
    - Okanagan 356570548: mouth 109.7 km from the Columbia, junction 1,260,702. The Similkameen
      (59.1 m³/s), which joins the Okanagan in Washington, rides on that path.
    - Kettle 356570045: 36.4 km, junction 1,196,910, 77.2 m³/s.
    - Both join the Columbia in the US, but here they are added to the Columbia in BC.
    - **Measured on the Columbia (356570372):**
      - Every placed outlet from 5024140 (drm 1,232,040) down to the border is FWA-high by 85-164
        m³/s: 1,148.6 vs PCIC 1,063.2; 2,116.4 vs 1,952.7; 2,835.5 vs 2,671.9 at the border outlet
        5025132.
      - **27 of 96 placed Columbia outlets** fail the 5% agreement, all in this stretch, out of 546
        disagreements job-wide. Every Columbia segment in that stretch carries the excess.
    - Smaller cases of the same kind: 300.625474.330225 and .365118 (Moyie/Yahk, Kootenay); Smoky
      tributaries (SMOK); 200.948755.780133 (LPCE); 700.317921 (INKR).
  - **Tributaries that reach the parent through a side channel or reservoir flowline.** 11,659 main
    stems have no equality match and touch a side channel of the parent. Of these, 187 carry placed
    flow (1,906 m³/s), projected to the nearest point of the main.
    - The Parsnip (166 m³/s) and Finlay (122 m³/s) form the Peace at Finlay Forks. They get junctions
      **80 km apart** on the Peace main line: 1,786,595 and 1,866,918. Every Peace segment between
      them carries the Finlay but not the Parsnip. Tracing the network (the junction of the flowline
      each mouth touches) gives 1,831,969 and 1,846,308.
    - Other examples: Nass trib 500.056359 is 2.6 km off; CLRH 300.863560, 15.8 km; CLAY
      930.302211.132423, 17.5 km.
    - Where placed outlets lie between the projected and the traced junction, **34 of 56** on these
      lines read FWA-high against PCIC. For equality-junction lines that touch a side channel (#5
      residual), 18 of 25 do.
  - **Side channels.** 11,342 side channels end on another side channel (braids), not on the main.
    Another 6,981 end on a line whose path does not reach their `watershed_key` (distributaries); one
    of them is projected 11 km. They carry little placed flow (4 lines, 6.9 m³/s), so the effect is
    small, but they are the same defect.
  - **Why QA passes.** Finding 2.
  - **Fix.**
    - Take the junction from the network, not from proximity. For each line, find the segment its
      mouth touches (`ST_DWithin(mouth, s.geom, 1)` on another blue line). If that is the wscode
      parent or the `watershed_key` line, keep the current junction: equality, else the touched
      measure. Otherwise make the touched line the parent, at the touched measure; its own path then
      carries the water on.
    - If the mouth touches no line (all 19 flow-carrying cases are on the BC boundary), give the line
      **no path**. Its water leaves BC and must not be added to a BC river. Say so in the README.
    - Because touched-line parents can loop in braids, make the walk at 01_paths:107-108 `RAISE` when
      it stops on a revisit, instead of truncating silently.
    - Expect placement to move: the Okanagan and Kettle outlets become FWA roots. Re-measure the
      Columbia outlets 5024140 to 5025132.

- **[fragile] sql/qa.sql:24-37, 56-70: no QA test can fail on Finding 1.**
  - The agreement test allows 10% of outlets to disagree. The 27 Columbia outlets, and the ~50
    side-channel-junction outlets, fit inside that budget: 35,834 of 36,380 agree.
  - The drop test sees only decreases. A tributary joined too high shows up as an *increase* at the
    wrong place, which is a step up and passes.
  - **Add an assertion on the path table itself:** every `pcic_blk_parents` row whose junction point
    is more than ~10 m from the line's mouth must be explained, either by the touched line or by an
    equality junction whose mouth meets a side channel. Measured today: **4,101** main-stem
    geometric junctions sit > 1 km from their mouths.
  - Restore the defect and watch the test fire. On the current table it must fail on 356570548
    (Okanagan).

## Checked and fine

- **Equality junction.** It cannot pick the wrong segment in practice where the mouth meets the
  parent: 36 of ~1.47 M lines are > 100 m off, and none has a placed outlet in the gap.
- **Paths.**
  - 1,571,322 parent rows, all with a junction.
  - 1,571,322 paths, 0 truncated.
  - No line has two wscodes or two watershed_keys.
  - One wscode has two main lines.
  - 6 lines are orphaned by 6010-only or side-only parent codes, with 0 placed outlets above them.
- **Segment-boundary ties.** 161 outlets sit exactly on a segment start, and 1 lies 0.002 m outside
  its segment. 06, 07 and qa.sql test 1 use the same `(seg_measure, drm, depth, subid)` order, and a
  junction equal to an outlet's measure counts as above it in the function, in 06 and in 07 alike.
- **No ORDER BY compares drm across blue lines.** In 06/07 each step matches one line. qa.sql orders
  within one segment or one line.
- **Shell.**
  - `n=$(…)` and `qa=$(…)` propagate psql failure under `set -e`.
  - A failed group in the `xargs -P 4` over 07 exits 123.
  - Demotion stops with exit 1 after 10 rounds.
  - No psql variables inside `$$`.
- **Accepted, not flagged.** `set -x` printing `DATABASE_URL`, the documented lut-area limitation, and
  the `extras/README.md` bchamp upload lines.
