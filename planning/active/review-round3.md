# Code-check round 3 (#14): the tolerance mechanism, and whether 1 mm covers it

Reviewer: subagent, 2026-10-11. All probes were read-only: hand-written SELECTs and TEMP
tables over `whse_basemapping.fwa_stream_networks_sp`, `fwapg.blk_paths`, and the
intermediate build in `whse_basemapping.pcic_fwa_crosswalk`, whose placement matches this
branch's. No job SQL was piped into psql. The probe files are in the session scratchpad
(`r3/p1-p11.sql`).

## The mechanism

The job decides which side of a junction something is on by comparing two measures that
should name the same point but come from different computations:

- FWA route measures (`downstream_route_measure`, `upstream_route_measure`)
- `drm + ST_LineLocatePoint(...) * length_metre`, which gives outlet measures in 02 and
  touch-junction measures in `blue_line_paths.sql`
- arithmetic offsets, such as the move's landing

The shared assumption is that these differ only by float noise, so the earlier rounds added
a 1 mm band at each comparison. The data agrees with that assumption only in part:

- **`upstream_route_measure` does not agree with the next segment's
  `downstream_route_measure`.** Over 4.9M FWA boundaries, 68,221 have a gap of 1 mm to 1 cm
  and 68,524 overlap by 1 mm to 1 cm (3,384 by more than 2 mm, at most 9.3 mm). So the
  comment in 06, 07 and qa.sql that "adjacent segments' measures differ in the last digits"
  is false for `urm`.
- **`drm + length_metre` does agree with the next `drm`.** It overshoots the next start by
  more than 1 mm at only 52 boundaries (at most 3.07 mm), even though `length_metre`
  differs from `urm - drm` by 1 mm to 1 cm on 252,666 segments. Every measure the job
  builds from `drm` (+ `length_metre`) therefore sits inside the 1 mm band, and the one
  that reads `urm` does not.

The author's enumeration holds for 06, 07 and qa.sql. Every cross-source comparison there
carries 1 mm, and the ones left exact really are same-source (segment `drm` against segment
`drm`, or outlet against outlet on one segment). The exposure is upstream of those files,
in which field a measure is built from. Only one consumer reads `urm` for a position:
the move's landing.

## Findings

- **[fragile, near-miss in the current placement]**
  `extras/pcic_crosswalk/sql/pcic_crosswalk06_subbasins.sql:53` (and the band at :90).
  - **The defect.** In a move that skips unusable segments, the landing
    `least(x.drm, b.urm) - 0.001` is 1 mm below **b's own `urm`**. The point that decides
    parenting is the **start of the skipped segment directly above b**. Lines join there,
    and that start can lie up to 9.3 mm below `b.urm`. When the overlap exceeds 2 mm, the
    moved outlet lands more than 1 mm above that junction, so the step>0 test
    `o.drm <= J + 0.001` fails. That tributary then skips the moved outlet, which is the
    round-2 class (0 flow on 356567538) produced by the move itself.
  - **It is one step away today.** Outlet 5014089 is the one skip-move of the six. It lands
    on 707098394 at 15307.561147. The skipped segment 707098172 (no watershed) starts at
    15307.560311, and tributary 356367323 joins exactly there (June flow 3.33 m3/s; the
    overlap is 1.84 mm). The landing is 0.84 mm above that junction, which leaves 0.16 mm
    of the 1 mm band.
  - **What happens when it fails.** 356367323's segments go to 5014089's parent 5014104,
    and take a share of a local area that does not hold their area. Segment b carries
    5014089's q_acc without the tributary, although the tributary joins above b.
  - **How often it can.** 9 boundaries province-wide have all three conditions: a usable
    lower segment, an unusable segment above it, more than 2 mm of overlap, and a line
    joining at the unusable segment's start. So it is rare, but a skip-move is exactly
    what selects these boundaries.
  - **What the QA sees.** Test 1 cannot see it, because x is off its vertex. Test 3 passes,
    because the tributary's outlets, if any, parent correctly to the outlet below. The
    ceiling test does not count it, because its population is junctions on segments with
    flow, and the skipped segment has none.
  - **Fix.** Land 1 mm below the start of the segment directly above b, not below `b.urm`:
    `least(x.drm, b.urm, n.downstream_route_measure) - 0.001`, where n is the next segment
    on x's line above b. Equivalently, take
    `least(x.drm, (SELECT min(downstream_route_measure) FROM fwa_stream_networks_sp WHERE
    blue_line_key = x.blue_line_key AND downstream_route_measure > b.downstream_route_measure))
    - 0.001`. Use the same value in the stacked band. Also correct the "differ in the last
    digits" comments, which are the premise this rests on.

## Where the mechanism reaches, checked

- **02 outlet measures (`drm + f * length_metre`).**
  - Placed outlets above their own segment's `urm`: 12, at most 0.82 mm.
  - Placed outlets above the next segment's start: 1 (5014089, 0.84 mm, the moved one
    above).
  - Outlets at fraction 1 (top of segment): 23, of which 20 sit at a junction, all within
    1 mm.
  - None exceeds the band. The province-wide ceiling for this formula is 52 boundaries,
    at most 3 mm.
- **blue_line_paths junction measures.** Code junctions are exact segment `drm`s.
  Touch junctions use the 02 formula. Junctions 1 mm to 1 cm from a segment start: 3
  province-wide, none within 1 m of a placed outlet. The `DISTINCT ON` there has no
  tie-break at a vertex, but both tie choices land within 1 mm, so this is harmless.
- **04/05 `blk_on_or_upstream` (exact `>=`, accepted for its operator).** The round-2 class
  also reaches placement. An outlet 1e-14 m above J on the segment below makes
  `J >= x.drm` false, so a PCIC child on that tributary cannot be placed there. This build
  has 4 such outlets (5012573, 5017485, 206006820 and 5014089). None has a PCIC child on
  the joining tributary, so there is no current effect. This note does not ask to reopen
  the accepted `>=`.
- **06 step>0 (:143) and 07 nearest/share (:79, :112).** These agree with each other, and
  QA test 3 holds them together from the 06 side.
  - **`+0.001` admits outlets genuinely above J.** That happens only within 1 mm of a
    mid-segment junction, on the junction's own segment, which is harmless.
  - **Two junctions within 1 mm** are treated as one vertex, which is correct.
  - **Segments shorter than 1-2 mm.** No segment with a fundamental watershed is shorter
    than 1 cm, so the band never spans a whole usable segment, and the move's landing
    always stays inside b.
- **Move, adjacent case.** When b overlaps s, the landing is `x.drm - 0.001`, below J. When
  there is a gap, it is `b.urm - 0.001`, more than 1 mm below J. Both are correct. Only the
  skip case above is exposed. Crossing other junctions in a skip-move changes 5014089's own
  q_acc (it now includes PCIC siblings). It does not change the total on b or below it, and
  the skipped segments are not output.
- **QA ceiling test.** Run by hand on the intermediate build: 18,941 junctions, 678 over,
  9 s. It is not vacuous (`count(*) > 10000`).
- **Regression tests 2 and 4.** Both return false when their rows are missing or flow is
  zero.

/Users/airvine/Projects/repo/fwapg/planning/active/review-round3.md
