# Code review, round 1: extras/pcic_crosswalk (staged diff)

Scope: every staged file under `extras/pcic_crosswalk/`, checked against the full code-check
checklist. I tested shell behaviour with small repros and measured the SQL findings against the
`whse_basemapping.pcic_fwa_crosswalk` already in the local fwapg DB (a read-only query; a
fetch run was in progress and I left it alone).

## Findings

- **[bug] pcic_crosswalk.sh:129-130**: the demotion loop never stops early.
  `psql -tXA` without `-q` still prints the command tag, so `n` is
  `"INSERT 0 N\nN"`, not `N`. Measured:
  `[: INSERT 0 1\n1: integer expression expected`, rc 2. `[ "$n" -eq 0 ] && break`
  never fires, and `set -e` ignores a failure inside an `&&` list. The script
  therefore always runs all 10 rounds of the expensive placement, `pcic_crosswalk03_select.sql`,
  and prints the error 10 times. The script also never says whether the rounds
  converged: if round 10 still demotes outlets, `pcic_demoted` holds demotions that the
  final crosswalk never applied. Fix: add `-q` to that psql call (06 already uses it), and
  warn or fail when round 10 still returns a count above 0.

- **[bug: silent data loss] pcic_crosswalk.sh:73-91, 115**: a failed reduction is cached as an
  empty batch. `fetch_batch` runs under `xargs … bash -c`, and that child shell does not
  inherit `set -euo pipefail`. Measured: an exported function under `xargs bash -c`
  runs on past `false` with `$-` = `hBc`.
  - So when `cdo` fails (its stderr goes to `/dev/null`), when `ncdump -v` fails on a file
    whose header passed the check, or when `cdo` is not installed, `awk` reads nothing and the
    empty `out.tmp` is moved to `data/monthly/<batch>.csv`. The function then returns 0.
  - That empty CSV looks the same as a legitimate missing outlet. It is not added to
    `missing.txt`, and the resume check (`[ -e "$out" ] && return 0`) skips that batch on
    every later run.
  - This has already happened in the local cache: `data/fetch.log` shows
    `NetCDF: HDF error` followed by `_mon.nc: No such file or directory`. Five 500-outlet
    batches are 0-byte CSVs: `batch_004_0007`, `batch_008_0051`, `batch_009_0066`,
    `batch_210_0083` and `batch_210_0088`. That is about 2,500 outlets that a re-run will
    silently treat as done.
  - The current `ncdump -h` check does catch truncated files: both in-flight partial `.nc`
    files returned rc 1. Data already written is not repaired by that fix.
  - Fix: inside `fetch_batch`, check the exit status of `cdo` and of both `ncdump` calls.
    Require `wc -l out.tmp` to equal `12 × n` minus any fill values before the `mv`, or fail
    the batch. Delete the five poisoned CSVs, and any other 0-byte CSV whose batch has more
    than one id, before the next run.

- **[bug] sql/pcic_crosswalk05_subbasins.sql:23-29 and sql/pcic_crosswalk06_segments.sql:40-60**:
  overlapping child catchments drive the local area negative. `local_area_ha` subtracts the
  FWA upstream area of every placed outlet anchored to `s`, and the 06 share subtracts each
  one that sits above the segment. Both assume those catchments are disjoint, but placement
  only requires each child to be on or upstream of its anchor, not of its siblings.
  Measured on the current crosswalk:
  - 544 ordered sibling pairs under one anchor have one child on or upstream of the other.
    334 of those are same-segment pairs, counted in both directions. 358 anchors are affected.
  - **904 sub-basins have `local_area_ha < 0`**. The children's summed area overshoots the
    anchor's own upstream area by a median of 0.94 of it. 332 of the 904 have nested
    siblings. The other 572 most likely come from child areas overlapping through the
    watershed-polygon lookup.

  Consequences:
  - When the local area is negative, `share` is 0 on every segment of the sub-basin. The
    sub-basin's `q_local` never appears on any segment, and at the anchor's own segment
    `q = sum(children)` instead of PCIC's `q_out`.
  - Where sibling c2 is placed upstream of sibling c1, the segments between them belong to
    c1, whose `upstream_subids` only lists outlets anchored to c1. So c2's flow drops out
    there and comes back below c1, and mainstem flow is not monotonic.

  Fix options: demote or flag siblings that nest on the FWA, or count an outlet only when it
  is not on or upstream of another counted outlet. Either way, use FWA nesting rather than the
  PCIC anchor when collecting "outlets above" in 06.

- **[bug] sql/pcic_crosswalk05_subbasins.sql:35-48 and sql/pcic_crosswalk06_segments.sql:78**:
  a placed outlet with no PNWNAmet series leaves a gap and misallocates its parent's flow.
  Such an outlet is in `missing.txt`, or sits in an empty batch as above.
  - It stays in `pcic_subbasins`, its area is subtracted from its anchor's local area, and
    06 still assigns segments to it.
  - But `pcic_subbasins_monthly` drops it through the `INNER JOIN pcic_outlet_monthly`, so
    every segment in its sub-basin gets no row at all.
  - Its anchor's `q_in` leaves out its flow, so the anchor's `q_local` carries that flow
    while being spread over an area that excludes the outlet's catchment.
  - The README says unplaced outlets are "not lost", but a placed outlet with no series is
    lost. 28 outlets are in `missing.txt` now, plus about 2,500 from the poisoned batches.
  - Fix: treat an outlet with no series as unplaced in 03, for example with a
    `no_series` flag, so its area and flow both fall to the next outlet downstream.

- **[bug, small] sql/pcic_crosswalk05_subbasins.sql:13-22**: placed outlets whose segment has
  no `fwa_streams_watersheds_lut` row disagree between area and flow.
  - 46 placed outlets sit on such segments. 369,063 non-6010 streams have no lut row, mostly
    edge types 1400, 1450 and 1100.
  - The `INNER JOIN` drops these outlets from `pcic_subbasins`, so their areas are not
    subtracted from the anchor. But 05's `q_in` (line 46) still subtracts their flow,
    because it filters only on `flag IS NULL`.
  - In 06, `pcic_segments` assigns segments to them, and then
    `INNER JOIN fwapg.pcic_subbasins` drops those segments, so they get no flow.
  - Fix: exclude such outlets in 01 by requiring a lut row for a candidate, so they never
    get placed.

- **[fragile] sql/qa.sql (whole file), pcic_crosswalk.sh:153-158**: QA cannot fail the run.
  Every test is a bare `SELECT … AS result` and nothing raises an error. So a run that
  fails mass balance, coverage or monotonicity still exports both `.csv.gz` files and
  then drops every `fwapg.pcic_*` staging table. That leaves nothing to debug from without a
  full re-run. The checklist rule applies here: a `.sql` file called by a script needs at
  least one check that raises.
  Fix: wrap the tests in `DO $$ … RAISE EXCEPTION … $$` (the script already sets
  `ON_ERROR_STOP`), or move the exports and the drop behind a check of the results.

- **[fragile] pcic_crosswalk.sh:63-107, 115**: a persistent non-422 failure turns into hours
  of retries.
  - Any non-422 failure that does not go away, such as a server outage or a 3xx redirect,
    also triggers halving. Note there is no `-L`, and PCIC has already moved one host to a
    301, which broke `extras/discharge`.
  - Each node of the halving costs up to 3 attempts, each up to `-m 1800` with `--retry 5`,
    plus 180 s of sleeps. It goes about 9 levels deep before a single outlet finally
    returns 1.
  - xargs keeps launching the remaining roughly 100 top-level batches after one fails. So
    an outage runs for many hours before the script exits non-zero.
  - Fix: add `-L`. Return 255 from `fetch_batch` when a single outlet fails for a reason
    other than 422, because xargs stops at once on 255. Consider halving only on 422.

- **[fragile, minor] qa_gauge.sh:36**: the gauge check can compare against the wrong stream.
  `FWA_IndexPoint(…, 500, 1)` takes the nearest stream to the gauge, and gauges often sit
  at confluences or bridges. The checklist rule is "Snapping is the same error". The script
  prints `gnis_name` and the gauge area but not the FWA upstream area of the snapped segment,
  so a match to a tributary still gives plausible-looking ratios. Fix: print
  `upstream_area_ha` next to `gauge_area_km2`, or take up to 5 candidates and pick the one
  whose area is closest to the gauge area.

## Checked and fine

- The NetCDF layout and the `awk` reshape are correct. A 500-outlet batch gives 6,000 rows,
  12 per subid, with smooth seasonal values, and singleton batches parse.
- The bbox-server pages are full: 48 pages of 1,000 plus 261 rivers, and 455 lakes. No
  subid is duplicated within or across the two collections.
- The PCIC tree has no cycles: 711 roots, maximum depth 532, and every one of the 48,716
  outlets reaches a root.
- QA blue_line_keys: 356364114 is the Fraser, 360887278 the Skeena and 360873822 the
  Bulkley.
- The argument order of `FWA_Upstream` in `pcic_on_or_upstream` matches the schema, and
  the same-segment (`lfid`) equality is deliberate.
- `set -x` printing `$DATABASE_URL` matches house style (`extras/discharge/discharge.sh`),
  so I did not flag it.
