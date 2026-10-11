# Code-check round 2 (#13)

Diff: `git diff 97334ce...HEAD -- extras research`. Probed read-only against the local fwapg (the current
`pcic_fwa_crosswalk` and `fwa_stream_networks_discharge_monthly` are the run13c build) and with a copy of
`ssnbler_check.sh` in the scratchpad.

## Findings

- **[bug] extras/mainflow_tree/ssnbler_check.sh:82 (with the `trap cleanup EXIT` at :74)**: if `DATABASE_URL`
  is unset, the script exits **0**. On macOS `/bin/bash` 3.2, an unbound-variable abort under `set -u` with an
  EXIT trap installed returns the status of the previous command (0), not 1. Reproduced with a scratch copy:
  `env -u DATABASE_URL /bin/bash ./ssnbler_check.sh 1 probe 400 KLUM 1` printed
  `line 82: DATABASE_URL: unbound variable`, then `exit=0`, and wrote no `runs.log` line. Minimal repro:
  `bash -c 'set -euo pipefail; f(){ true; }; trap f EXIT; echo "$UNSET"'; echo $?` gives 0 (1 without the
  trap). `${DATABASE_URL:?}` after the trap also exits 0. A loop or caller that reads exit 0 as "0 node errors,
  outlets match" passes a check that never ran. Fix: test it before the trap, with an explicit exit, e.g.
  `[ -n "${DATABASE_URL:-}" ] || { echo "DATABASE_URL is not set" >&2; exit 2; }` next to the other argument
  checks (tested: exits 2). `$DATABASE_URL` is the only variable expanded after the trap that can be unset.

- **[bug, small] extras/pcic_crosswalk/sql/pcic_crosswalk02_candidates.sql:65-68, :107**: the upstream-segment
  tie rule applies whatever PCIC's tree says. It is right when the tributary entering at the vertex is the
  outlet's PCIC **sibling**, but wrong when it is the outlet's PCIC **child** (PCIC routes it into this outlet,
  so the outlet is below the confluence). Of the 140 placed outlets sitting at the start of a segment above a
  junction (`localcode != wscode`), 12 have a placed outlet on the tributary entering there: 6 siblings and
  **4 PCIC children** (with sub-tributary children counted, 7 outlets in the build have a placed PCIC child
  joining exactly at their measure). Examples: 9001132 (CLAY, blk 354154798). This branch moved it from
  710207545 (below the junction, localcode `.075520`) to 710206828 (above it, `.112867`; `run13c_crosswalk.diff`).
  Its PCIC child 9001130 (`930.350962.112867`) joins at 3084.10028 = the outlet's measure. 4000204 and
  2007294 (Columbia) were already on the upper segment in #11. What follows from it:
  - `fwa_parent_subid` still makes the tributary a child (06, step > 0, `o.downstream_route_measure <= st.measure`
    with the junction measure equal to the outlet's), so `q_acc` includes the tributary. But `upstream_area_ha`
    is the upper segment's, which excludes it (9001132: 12,382 ha with a 7,367 ha child). So `local_area_ha` is
    understated by the tributary's area, and 07's shares for the sub-basin's other segments are inflated
    (clamped at 1).
  - The published crosswalk row (`linear_feature_id`, `localcode_ltree`) puts the outlet above a confluence
    whose flow its PCIC series includes. Anyone running `FWA_Upstream` from it gets an area without the tributary.

  The README's "at a tributary junction is the segment above it" and findings' "which is what a PCIC sub-basin
  outlet there drains" hold for the sibling case only. Possible fix: at a tie, take the lower segment when one of
  the outlet's PCIC children's blue lines enters at that vertex (its wscode equals the upper segment's
  localcode). Or accept it and say so in the README caveats. Scale: 4-7 outlets, so the user may well accept it,
  but the rule as written is not the one the rationale describes.

- **[fragile] extras/mainflow_tree/ssnbler_check.sh:81-85, header :16-17, README "exits with R's status"**: a
  failure before R starts (an unreachable database, or an ogr2ogr error) exits via `set -e` with ogr2ogr's
  status, 1. That is the same code `ssnbler_check.R` uses for "node errors or outlet mismatch", and no
  `runs.log` line is written. An R crash (for example an empty subset: ogr2ogr writes a 0-feature layer with
  exit 0, and `lines_to_lsn` then fails with `st_geometry(in_edges)[[1]]: subscript out of bounds`, probed in
  scratch) is also exit 1. It does at least log `lines: ? node errors: ?`. So exit 1 alone does not mean a
  topology failure. Low impact for interactive use. For scripted use, a distinct code for "no result" (e.g. 5
  when the log has no `node errors:` line, and an `|| exit 5` on the ogr2ogr) would separate them.

## Checked, no finding

- 02 SQL validity: the `DISTINCT ON (s.blue_line_key)` ORDER BY still leads with `s.blue_line_key`. The
  qualified `s.downstream_route_measure` in both ORDER BYs is the input column, not the computed output alias
  of the same name, which is what is wanted. Upper-segment pick: `ST_LineLocatePoint` is 0 at its start, so the
  measure equals that segment's `downstream_route_measure`, inside `[drm, urm)`. The lower segment would have
  given `urm`, outside its half-open range, so nothing downstream (06/07 compare by `seg_measure` first) is
  pushed out of range. The side-move lookup uses the same tie order as the main block, so the dedupe DELETE
  (`distance, linear_feature_id, ctid`) sees the same segment in a tie, not a different one. The `LIMIT
  :num_features` cut and `candidate_rank` keep `linear_feature_id`, consistent with each other.
- qa_topology.sql: `bc_outline` follows the file's existing pattern (temp tables without DROP, one `psql -f`
  session per run from `mainflow_tree.sh`). The GiST index serves the `ST_Intersects` lookup. The subdivided
  union covers the same area as the original (round-1 tangency check).
- ssnbler_check.sh lock: a `.lock` with no pid file is taken over. The only window where that is wrong is
  between another run's `mkdir` and its `echo $$` (microseconds), so a collision needs two starts at the same
  instant. The "already running" exit happens before the trap, so it never removes the other run's lock.
  `set -e` failures after the trap keep their status (only the unbound-variable case loses it). R's `getwd()`
  and `pwd -P` are both physical paths, so the worker tag matches.
- Docs vs findings: the run times (28-33 min, 16 min paths, 6 min segments, 20 min tree job, QA 1.5 min), SSNbler
  numbers (28 GB at 21,700, 52-54 GB at 29-30k, 3.5/7.5/16/20 GB, 23/35 min, MSKE 4 vs 2, ZYMO), "27 of 29 groups",
  "about 1% of outlets" (449 of 48,716) and the Toba's first 122 m in three segments (206063691, 206063674,
  206063646 have no flow; checked in the DB) all agree with findings.md and the database.

## Outside the diff (pre-existing, for the record)

- **extras/pcic_crosswalk/sql/pcic_crosswalk07_segments.sql:94-96** together with `fwapg.blk_on_or_upstream`'s
  `u.measure >= drm_a`: a code junction's measure is the `downstream_route_measure` of the main-stem segment
  starting at the junction. So a tributary that is an FWA child of that segment's sub-basin counts as passing the
  segment above the confluence, and that segment carries the tributary's flow. Measured on the current build:
  of 5,892 single-step tributaries with June flow over 1 m3/s at such junctions, 1,464 put the jump on the
  segment above the junction. Example: blk 356362488, segment 701317184 (230 m) carries 684.85 m3/s against
  13.97 on the next segment up, tributary 670.88. This is one short segment per junction, and the files are
  untouched by this branch. It is the same `[drm, urm)` convention the new tie rule cites, so it is worth an
  issue: the passing test should be strict (`>`) for segments, or should compare by segment.
