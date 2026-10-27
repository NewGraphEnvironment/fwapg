# Task: PCIC crosswalk: Nechako Reservoir outlets unplaced, routed flow about zero in LEUT, UEUT, UNRS, LNRS (#24)

**If we do it:** FWA segments in the Nechako Reservoir groups carry PCIC's routed flow, instead of about zero. **If we never do:** routed flow there is about zero on every segment, so any consumer (wet's default pick, NewGraphEnvironment/wet#57) has to fall back to another estimate across four watershed groups.

## Context

PCIC's tree sends the Nechako Reservoir out through the Skins Lake spillway and the Cheslatta. The FWA sends it the natural way, down Knewstubb Lake, through Kenney Dam and into the Nechako canyon. Measured on the local build (crosswalk b1a71083…):

- PCIC has one lake outlet for the whole reservoir, **1007550** (subtree 484). It is placed on the top of FWA blue line 356209076, a 1.87 km Cheslatta tributary in CHES that starts 62 m from Ootsa Lake. The FWA does not connect that line to the reservoir.
- Every outlet above 1007550 must sit on or upstream of it on the FWA, and none can. So 479 are `broken_chain`, and 483 of the 487 in the four groups are unplaced (LEUT 72/72, UEUT 203/203, UNRS 110/111, LNRS 98/101). Their runoff goes to 1007550's sub-basin and accumulates down the Cheslatta, which is correct: 156.4 m³/s at the spillway, matching PCIC.
- The reservoir's FWA segments belong to the nearest placed outlet on or below them, which is 1002307 on the Nechako at 280,462 m. That outlet carries 0.36 m³/s of local runoff, so the reservoir's segments read about zero.
- The FWA exit is the foot of Knewstubb Lake (waterbody 329318438) on the Nechako main line, blue line 356362759, at 288,852 m. Below it is the canyon (edge 1000 and small 1200 pools) down to the Cheslatta confluence at 280,379.
- Gauges (1951-2012): 08JA013 Skins Lake Spillway, observed 95.5, PCIC 156.4, FWA 156.4. 08JA017 Nechako below Cheslatta Falls, observed 73.3, PCIC and FWA 162.2. 08JA015, 08JA016 and 08JA028 have FWA flow of about 0 against PCIC's 3.9, 0.68 and 45.0. 08JA014 has no PCIC outlet. PCIC models no Kemano diversion, so it is high at both regulated gauges. That is PCIC's model error and is out of scope.

## Decided at the gate (2026-10-27, user)

1. **Below the dam, the water follows PCIC's spillway route.** The reservoir's accumulated flow goes to the spillway outlet 1008709 and down the Cheslatta. The canyon below Kenney Dam keeps only its own local flow. 08JA013 and 08JA017 stay matched to PCIC.
2. **Rebuild and publish on this branch**, as in #42. That means 1981-2010 with `WEEKLY=1`, then the 1951-2012 reference run with `DAYS=1` (built last), then upload to fresh-bc and read the files back.
3. Taken by default and named in the PR: in the published `pcic.fwa_crosswalk`, `fwa_parent_subid` is the **flow** parent. For 1007550 that is 1008709. The position parent stays in the staging table `fwapg.pcic_diversions`, so the published schema does not change.

## Design

A committed list of diversions, `sql/pcic_crosswalk03_diversions.sql`, with one row for now: PCIC lake outlet 1007550, FWA exit at the lowest segment of waterbody 329318438 on blue line 356362759, and a note.

- **Placement (04):** a listed outlet takes its listed FWA position whatever its anchor says. Its PCIC children are then chain-tested against that position as usual, so the reservoir inflows place normally. `candidate_rank` is NULL, and `distance_to_stream` is the real distance.
- **06 subbasins:** the below-junction move skips listed outlets. `fwa_parent_subid` is computed by position as now. For a listed outlet the position parent (1002307) is recorded in `pcic_diversions`, and `fwa_parent_subid` is set to its nearest placed PCIC ancestor (1008709). Local area subtracts children by position parent, so the reservoir's area comes off the canyon and not off the 0.8 km² spillway sub-basin.
- **07 segments:** children are joined by position parent. Area is subtracted for all of them. `upstream_subids` takes only children whose flow parent is the sub-basin. A diverted outlet is added to `upstream_subids` of the receiving outlet's own segment, where its water enters (share 1 there already).
- **06_daily and the per-year days:** unchanged, because they follow `fwa_parent_subid`.
- **Refusals:** a listed subid that is not a lake outlet in `pcic_outlets`, a waterbody not on the listed blue line, or a receiving ancestor that is unplaced. Each raises and stops the job.

## Phase 1: Baseline and tests first

- [ ] Record the baseline in `findings.md` and in a log under `extras/pcic_crosswalk/logs/` (CSV): placements per group, mean annual flow on the reservoir's FWA segments, near-zero segment counts per group, and the five Nechako gauges.
- [ ] Add QA tests to `sql/qa.sql`, using ceilings where a count can vary:
  - at least 90% of the four groups' outlets that have a candidate are placed
  - Knewstubb's exit segment carries 1007550's PCIC flow within 5%
  - the canyon segment below the exit carries under 1 m³/s
  - 08JA013's outlet 1008709 is within 5% of PCIC
  - each diversion's position parent and flow parent are both recorded
- [ ] Exclude listed diversions from "every FWA child on another blue line joins above the start of its parent's segment".
- [ ] Show the new tests fail. Run them against the current `pcic.*` tables in a scratch copy, and record the failures.

## Phase 2: Diversion list and placement

- [ ] Write `sql/pcic_crosswalk03_diversions.sql`: the list, the derived exit position and the refusals. Call it from `pcic_crosswalk.sh` after 03_prepare. Copy it with the job's code, as the per-year days copy theirs.
- [ ] `sql/pcic_crosswalk04_select.sql`: give listed outlets their listed position, bypassing the chain test.

## Phase 3: Flow tree and weights

- [ ] `sql/pcic_crosswalk06_subbasins.sql`: skip the move for listed outlets, record the position parent, override the flow parent, and compute local area by position parent.
- [ ] `sql/pcic_crosswalk07_segments.sql`: join children by position parent, and add the diverted outlet at the receiving outlet's segment.
- [ ] `./pcic_test.sh` still passes (06_daily is unchanged).

## Phase 4: Docs and research

- [ ] README:
  - placement (step 4) and the listed diversion
  - flow at outlets (step 5) and segments (step 6) with the diversion
  - `fwa_parent_subid` meaning in the `pcic.fwa_crosswalk` table doc
  - a Nechako Reservoir caveat: the spillway route, the dry canyon, no Kemano in PCIC (08JA013 and 08JA017 high)
  - the Cheslatta regulated-flow flag checked against the result
  - the drainage and review counts updated after the rebuild
- [ ] `research/pcic_crosswalk_diversions.md`: the reservoir case, the measurements and the mechanism. Add a row to `research/README.md`.

## Phase 5: Rebuild and measure

- [ ] Commit, then run `YEARS=1981/2010 WEEKLY=1 ./pcic_crosswalk.sh`, then `DAYS=1 ./pcic_crosswalk.sh`, from committed trees. Export `DATABASE_URL` and `PGSERVER` for the session, and keep the URL out of committed logs.
- [ ] Measure against the Phase 1 baseline:
  - placements in the four groups
  - reservoir segment flows and near-zero counts per group
  - `qa_report` deltas
  - `qa_gauges.sh` over both periods: 08JA013, 15, 16, 17 and 28
  - the drainage and following flags on the Cheslatta and the reservoir
  - the clamp counts
- [ ] Record the measurements in `findings.md` and a log CSV.

## Phase 6: Publish and read back

- [ ] Upload the 63 parquet files, then the `.csv.gz` files, to `s3://fresh-bc/fwapg/extras/` (`extras/README.md` order). Check each object's size against its file.
- [ ] Load `load/pcic.sql` and `load/pcic_run.sql` from fresh-bc into a scratch database. Read one year over HTTP and match its `pcic.series` row.

## Phase 7: Follow-ups

- [ ] File an issue for the other large broken-chain clusters, all inside BC: Kootenay 5025228 (140), Pend-d'Oreille 5013906 (92), Fox 206008363 (44), KOTL 5014312 (32), Chilcotin 4007152 (31). It asks whether any of them is the same kind of case.
- [ ] Comment on wet#57 that the four groups now carry routed flow, with numbers.

## Owed at the end (reported, done after merge)

- [ ] Close #24 by hand, with a comment naming the PR (a merge into `newgraph` does not close it).

## Validation

- [ ] Tests pass (`pcic_test.sh`, and `qa.sql` all `t` on both builds)
- [ ] `/code-check branch` clean before the PR (three-round floor)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification:

- The new QA tests fail on the old build and pass on the new one.
- The reservoir's segments carry flow that rises toward Knewstubb's exit and equals 1007550's PCIC outflow there.
- The canyon below the exit carries about 0.36 m³/s.
- The spillway and Cheslatta flows are unchanged within 5%.
- The fingerprints of every run outside the four groups and CHES/Nechako move only where the weights changed. This is checked by diffing `segment_weights` by group against the published files.

