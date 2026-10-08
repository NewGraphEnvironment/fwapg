# Review round 7: side-channel move and three-level vote (commit 4929c8c)

## Scope and method

This round covers two changes:

- the side-channel move in `sql/pcic_crosswalk02_candidates.sql` (lines 70-135);
- the vote in `sql/pcic_crosswalk03_prepare.sql` (lines 21-43) and `sql/pcic_crosswalk04_select.sql` (lines 71-80).

All measurements are read-only SELECTs on the local DB, and the staging tables match the build:

- 37,402 placed, 1,157 broken_chain and 136 demoted.

To reconstruct what the code did:

- **Pre-move candidates.** I re-ran the candidate query (tolerance 150, 5 features) and wrote it
  to CSV. It returned 92,508 rows. Of those, 5,541 are side candidates on 4,501 outlets.
- **Moves.** I recomputed `side_moves` from those side candidates.
- **Baseline.** The pre-change build is the exported `pcic_fwa_crosswalk.csv.gz` (07:35; 36,527
  placed, 2,075 broken_chain). Old flow is the annual mean of the old discharge export on the old
  placed segment.
- **"Ok".** An outlet is ok when it is within 5% of PCIC. Old ok is counted only where the outlet
  was the sole outlet on its segment (35,107 outlets).

## Enumeration (each case: right / wrong, measured)

### Side-channel move

- **Side channel coded with the watershed_key of a different main: right (cannot occur).** The
  watershed_key line has the side channel's own wscode in all 5,353 moves (0 mismatches). For the
  same reason, the missing `NOT wscode <@ '999'` filter in the move query matters in 0 cases.

- **Side channel whose watershed_key line is not the river PCIC follows: WRONG, and it is the
  common case.** PCIC tributary outlets often snap to the last reach of a tributary. That reach is
  coded as a side channel of the big river: a 1450 connection line in a double-line river, a 1350
  anabranch, or a 1100 secondary channel. Because the move is unconditional, the outlet is moved
  onto the trunk river.
  - 433 outlets were right before (sole on their segment, within 5%) and sat on a side channel that
    is now moved. Of these:
    - 326 are now placed on the main river and are high: median 68× PCIC, 252 of them over 10×.
      By edge type: 140 were 1450, 92 were 1350 and 89 were 1100.
    - 107 are now unplaced (94 demoted, 13 broken_chain). Their subtrees hold 1,164 outlets.
  - Of the outlets whose rank-1 candidate was a side channel and that are now placed on the moved
    point, only 276 of 592 are within 5% of PCIC.
  - Examples:
    - **Kitsumkalum, 8007998 (130.6 m3/s).** It was on braid 360222216 at 3.4 m, which matched
      PCIC. The braid candidate was moved onto the Skeena and merged with the Skeena candidate at
      87 m, which was the only candidate left. The outlet was then demoted. Outlets within 5% in
      its 111-outlet subtree fell from 109 to 100.
    - **Skeena tributary outlets.** 8007615, 8007620, 8007622, 8007636, 8007645 and 8008031
      (30-110 m3/s) are now on the Skeena at 1,011-1,559 m3/s.
    - **Nass side channel 360218614/18.** 12001174, 12001175, 12001190 and 12001196 (1.5-4.5 m3/s)
      are now on the Nass at 250-949 m from their probe points, two of them at the same measure.
      Their q_acc is about 770 m3/s. **Ansedagan Creek (gauge 08DB013) now carries 0 flow on all
      22 segments.** It is in the gauge table (q_fwa 0.000), but the README's list of remaining
      disagreements does not mention it.
    - **Spillimacheen distributary 356364751.** Its watershed_key is the Spillimacheen, and its
      path runs through Baldy Channel to the Columbia. 5020213 was moved to the Spillimacheen main
      stem, which reaches the Columbia 15 km higher, and 5020142 (on Baldy Channel) was moved onto
      the Columbia. Both are now demoted. The Spillimacheen's 32 m3/s now enters above 5020143.
  - Knock-on effects:
    - 50 outlets that did not move are now wrong because a PCIC sibling now sits above them on the
      FWA. Columbia 5020143, 5020146, 5020151, 5020171 and 5020177 went from 59.8 (= PCIC) to
      91.8 m3/s (+54%); 9005811 is +10%.
    - 155 outlets are newly unplaced because their anchor moved: 106 of those anchors had been on
      a side channel.
  - Totals:
    - 638 outlets that matched PCIC before no longer do (376 placed wrong, 262 unplaced). Against
      that, 1,114 newly placed outlets are within 5%.
    - Outlets over 10× PCIC: about 24 before (sole basis) and 358 now, 275 of them on a moved
      target.
    - Outlets within 5%: 99.1% before, 98.0% now. The QA thresholds (90% and 95%) do not see this.
    - The gauges do not see it either, because gauges sit on trunks, not at tributary mouths.

- **Distributaries and lake construction lines: wrong (as above).** The Spillimacheen case is a
  distributary. The 1450 connection lines are 3,072 of the 5,541 side candidates.

- **Side channel that is the only channel, with the main stem far away: wrong where the side
  channel is the river PCIC follows.**
  - Placed outlets beyond the 150 m tolerance went from 0 to 151 (max 966 m; 49 over 500 m).
  - Moved targets that are placed: up to 150 m, 3,422 of 3,886 are ok; over 150 m, 106 of 199
    are ok.

- **Move jumps to a different reach of the main stem: right (rare).** Among rank-1 moves that are
  placed, 3 targets land more than 100 m below the side channel's mouth on the main, and 0 land
  above its top. The measure follows the probe point, and the problem is the move itself, not
  where it lands.

- **Duplicates after the move (ctid tie-break, re-rank join): right.**
  - The dedupe removed 4,871 rows.
  - 0 duplicates remain on (subid, blue_line_key) or on (subid, linear_feature_id).
  - Ranks run 1..n without gaps on all 38,695 outlets.
  - The `(distance, lfid, ctid)` row comparison is a strict total order, so exactly one row is
    kept. lfid is unique per subid after the dedupe, so the re-rank join is exact.

- **distance_to_stream after the move: consistent, but it feeds the defect above.**
  - The near rule and rank use the main-stem distance, so a moved candidate drops in rank.
  - The vote still picks it when the voters were moved too: 12001196 went to 250.9 m on the Nass
    with 2 of 4 votes.
  - Snap QA has no test on distance. In the report, p99 is 93 m and the max is 966 m.

- **Side channels left unmoved (188 candidates on 179 outlets, no watershed_key line within
  1 km): right.** 53 outlets are placed on them, and 51 of those are within 5%.

### Vote

- **Vote overrides a closer, valid candidate: right.**
  - On 371 outlets the vote overrides a valid rank-1 candidate. 336 of them are within 5%.
  - Of the 35 that are not, 30 were not ok, or not placed, before either.
  - 5 were ok before:
    - 9000091 and 11003645 matched only while their 4-6 upstream outlets were broken_chain. All of
      those are placed now, and the vote agrees with PCIC's tree.
    - 12001196 and 5020171 are side-move effects.
- **Small outlet swamped by a big branch: right by construction.** Voters are only the outlet's own
  PCIC-upstream outlets, and they are counted as distinct outlets, not by subtree size. A candidate
  downstream on another candidate's path always scores at least as high. Ties go to the nearest,
  so an override needs strictly more votes.
- **Voters that are themselves unplaceable: right.**
  - no_candidate and outside-BC outlets have no candidates, so they have no voter rows.
  - I re-scored every placed outlet that has at least 2 candidates (33,215) using only voters that
    end up placed. That changes 0 choices. The same harness with all voters reproduces the build
    exactly (0 changes), and with nearest-only it changes 371.
- **Interaction with demotion and the 25 m near rule: right on its own.** The demotion count rose
  from 93 to 136, and the extra demotions are side-move consequences (Kitsumkalum, 5020142,
  5020213). The near rule is what fixed Nicola 3000039.
- **Three-level limit: not measured.** A re-score that compared 2 and 6 levels ran over 10 minutes
  without an index on the CTE, so I cancelled it.
- **Cost: fine.** pcic_voters has 121,706 rows over 28,867 outlets, an average of 4.2 per outlet.

### Previously-right cases

| Case | Before | Now | Result |
|---|---|---|---|
| Birkenhead 4008011 | 173.14 = PCIC | 173.14 = PCIC | right |
| Columbia 5024140 | = PCIC | 1,063.18 = PCIC | right |
| Columbia 5025132 | = PCIC | 2,671.89 = PCIC | right |
| Nicola 3000039 | on Clapperton Creek | on 356363343 (Nicola), 8.37 = PCIC | fixed |
| Kitsumkalum and Cayoosh path QA tests | pass | pass | right |
| **Kitsumkalum outlet 8007998** | placed, = PCIC | demoted | **worse** |
| **Columbia 5020143-5020177** | = PCIC | +54% | **worse** |
| **Ansedagan Creek (gauge 08DB013)** | has flow | 0 flow | **worse** |

Pre-existing and not caused by this commit: 4002922, the PCIC subid at the Cayoosh gauge, sits on
the Fraser at 84 m. Its q_acc is 1,676 against PCIC's 17.1, and the position is the same as before.

## Findings

- **[severity: bug]** extras/pcic_crosswalk/sql/pcic_crosswalk02_candidates.sql:70-119 — Every
  side-channel candidate is replaced by the nearest point on its watershed_key line.
  - The side channel is often the river PCIC follows: a tributary's last reach coded as a 1450
    connection line, 1350 anabranch or 1100 channel of the trunk river, or a distributary.
  - Measured damage:
    - 638 outlets that matched PCIC before no longer do. 326 sit on trunk rivers at a median 68×
      PCIC flow, and 262 are unplaced, carrying 1,164 outlets in their subtrees.
    - 50 unmoved trunk outlets are now high, for example Columbia 5020143-5020177 at +54%.
    - Outlets over 10× PCIC went from about 24 to 358.
    - The Kitsumkalum outlet (130.6 m3/s) is demoted.
    - Ansedagan Creek (gauge 08DB013) has 0 flow.
    - 151 outlets are placed beyond the 150 m tolerance, up to 966 m.
    - Only 276 of 592 rank-1 side outlets placed on a moved point are within 5%.
  - The net counts improved (+875 placed), but the commit and README report 98% within 5% as a
    success. It was 99.1%, and the QA thresholds hide the drop.
  - Fix: do not replace. Add the main-stem point as an additional candidate and keep the side
    candidate, so the vote and anchor choose between them. Voters on a braid that rejoins above the
    main point score the main point, while the outlets above a tributary that enters through a
    connector score the connector.
  - Re-measure against this round's list of regressed outlets and add QA tests:
    - Kitsumkalum outlet 8007998 placed and within 5%;
    - Columbia 5020143 within 5%;
    - Ansedagan Creek 360884999 has flow.
