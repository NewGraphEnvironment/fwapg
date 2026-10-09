# Task: PCIC crosswalk: drainage check at every placed outlet (#7)

`extras/pcic_crosswalk` (#5, PR #6) is checked by internal consistency: flow accumulated on the FWA matches PCIC's outflow where the two networks agree. That is partly circular. If a chain of outlets is shifted onto a neighbouring FWA stream, runoff is relocated but still sums correctly. PCIC publishes no sub-basin polygons or areas (`bbox-server/collections/upstreams` gives a point and `upstream_subids` only), so there is no PCIC drainage area to compare with FWA upstream area directly.

Branch off `newgraph`; PR targets `newgraph`.

## Approach

Two measures per placed outlet, both cheap with the tables the job already builds:

1. **Drainage size, PCIC vs FWA.** PCIC upstream network length (sum of `ST_Length` of PCIC river segments in the outlet's PCIC subtree, from `fwapg.pcic_rivers` and the `dowsubid` tree) against FWA upstream area at the placed segment (`fwa_streams_watersheds_lut` → `fwa_watersheds_upstream_area`, as `pcic_crosswalk06_subbasins.sql` does). PCIC's network has a roughly fixed density, so length / area should be stable within a region: normalise the ratio by its median over the outlet's watershed group and flag outliers (start at > 2× or < 0.5×, set from the distribution). This catches a small outlet on a big river (the > 10× PCIC class) and a big outlet on a small stream.
2. **Did the chain move it?** FWA upstream area at the placed position against FWA upstream area at the outlet's nearest candidate (rank 1 in `fwapg.pcic_candidates`, no chain constraint). Where they differ a lot, placement overrode proximity; that is either the chain fixing a confluence (Nicola) or the chain dragging an outlet onto the wrong stream. Reported, not tested: on its own it cannot say which.

Before trusting the check, **seed known errors** and confirm it fires: place the Nicola main-stem outlet (3000039) back on Clapperton Creek, and a few tributary outlets on the river they join (the round-7 class), in a scratch copy of the crosswalk, and check they land in the outlier list.


## Phase 1: Rebuild and measure
- [ ] Rebuild the staging tables from the job's `data/` cache (network load, `00`–`07`; no download) on local fresh-db
- [ ] PCIC upstream river length per outlet (recursive over `dowsubid`, `ST_Length` of `fwapg.pcic_rivers`; lakes contribute 0)
- [ ] FWA upstream area at each placed outlet's segment and at its rank-1 candidate
- [ ] Distribution of length / area by watershed group; pick the normalisation (WSG median) and the outlier threshold from it, with numbers in `findings.md`

## Phase 2: Validate the check
- [ ] Seed known misplacements in a scratch crosswalk (Nicola 3000039 on Clapperton Creek; tributary outlets placed on the river they join, from the round-7 list) and confirm each is flagged
- [ ] Cross-tabulate the outliers against existing evidence: the 85 outlets > 10× PCIC, the gauge disagreements (`data/qa_gauges.csv`), `candidate_rank > 1`, placed vs rank-1 area difference
- [ ] Inspect the largest outliers that no other check flags (a handful, by query and `ST_Distance`), and record what they are

## Phase 3: Encode in the job
- [ ] `extras/pcic_crosswalk/sql/qa_drainage.sql`: builds `fwapg.pcic_qa_drainage` (per placed outlet: PCIC length, FWA area, normalised ratio, placed vs rank-1 area, flags) and prints the outlier report
- [ ] `pcic_crosswalk.sh` step 5: run it before the export and cleanup, `\copy` the table to `data/qa_drainage.csv`
- [ ] A test in `sql/qa.sql` with a ceiling on the outlier count, set from Phase 1's measurement (and confirmed to fail on Phase 2's seeded errors)
- [ ] `extras/pcic_crosswalk/README.md`: what the check measures, its threshold, the result

## Phase 4: Hand off
- [ ] Comment the outlier list on #8 as its review sample (with the > 10× and gauge lists already there)
- [ ] Record measurements in `findings.md` and `progress.md`

## Validation
- [ ] Tests pass (`psql -f sql/qa.sql`, all `t`, and the new test fails on the seeded errors)
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

