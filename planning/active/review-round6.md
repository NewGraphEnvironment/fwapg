# Review round 6: rounds + deferred code junctions in sql/pcic_crosswalk01_paths.sql

Scope: commit 7f90f15. Covers rules 1-5 in sql/pcic_crosswalk01_paths.sql (lines 112-192), the
acyclicity argument in its header (lines 34-38), and the last two tests in sql/qa.sql. All
measurements are read-only SELECTs on the rebuilt local DB. pcic_blks, pcic_touches and
pcic_code_junctions were recomputed in CTEs.

Build state:
- Parent rows: 1,467,190 code, 71,331 touch, 29,671 touch_round and 37 code_deferred.
- touch_round rows by round: 1 = 24,955; 2 = 3,751; 3 = 773; 4 = 161; 5 = 28; 6 = 3.
- Round 7 added nothing, so the 37 deferred code junctions were inserted with round = 7. The
  second pass (round 8) added 0 rows.
- Confirmed:
  - Birkenhead 356360441 goes to side 355993478, which enters the Lillooet at 85,225. Outlet
    4008011 = 173.14 = PCIC.
  - Columbia outlets 5024140 and 5025132 = PCIC.
  - The Kitsumkalum is 'touch' (round 0) to braid 360222215, which is round 1 to braid 360222216,
    then to the Skeena.

## Enumeration (each case: right / wrong, measured)

1. **Round edges actually created: right.**
   - 14,698 go from a side channel to a sibling side channel. All have the same code and the same
     watershed_key; 0 go to a braid of a different main.
   - 14,820 go from a deferred main to a lower-code side channel, and 152 go from a deferred main
     to a lower-code main.
   - 1 goes from a main to a main with the same code. This is the only duplicate-main code in BC:
     200.692231.387879, where 359024601 (unnamed, 0 outlets, 2 lines upstream) touches the Beaver
     River 359572098 at 51,109.
   - All 14,972 main round edges come from mains that have a code junction, so they are deferred
     mains. No main without a code junction got a round edge.

2. **Is the acyclicity argument true? Not as written (fragile). The data has no cycle now.**
   - The header (lines 34-38) says a rule-3 edge "goes only to a line that had a parent in an
     earlier round". That is true, but it does not imply acyclicity: the target's own edge can point
     back to a line that is still unattached.
   - Rule 2 inserts side-to-own-main edges at round 0 whether or not the main has a parent. So a
     braid B of main X sits at round 0 pointing to X while X is still unattached. This happens when X
     is deferred, or has no code junction.
   - If X's mouth also touches B, X takes B in round 1. The ordering puts touched_depth DESC first,
     so B (same depth as X) wins over the side channel of P that X touches (one level shallower).
     The result is the cycle X → B → X.
   - A correct argument:
     - Every edge goes to an ancestor-or-equal code, so a cycle must stay inside one code.
     - Inside one code, side→side round edges point to lines inserted earlier, so a cycle must pass
       through a main.
     - A cycle is therefore possible only when a main takes a same-code round edge.
   - Measured:
     - 0 deferred or unattached mains have a mouth that touches their own braid.
     - 1 main took a same-code round edge (the Beaver duplicate above), and its target has a
       different parent chain.
   - The walk stops at revisits, and the DO block at lines 226-236 raises on any cycle. A future FWA
     load where a braid rejoins exactly at a deferred or transboundary main's mouth would therefore
     abort the build, not corrupt it.
   - Fix: only side channels may take same-code round edges, e.g.
     `AND (NOT t.same_code OR NOT b.is_main)` in the round insert. Alternatively, exclude targets
     whose current parent chain contains the source. Then fix the header.
   - Deferred rows (round = 7) and the second pass: right. Round r+1 sees round-r deferred rows, and
     a deferred edge goes to a lower code, so it cannot close a cycle.
   - Attaching to a line whose own parent comes later (round 0 → still-unattached main): covered
     by the cycle analysis above. When the main never gets a parent, the source's path simply ends
     at that main, which is consistent.

3. **Wrong neighbour via a round edge: right (measured 0).**
   - `touched.wscode @> own wscode` excludes sibling tributaries at a confluence, because neither
     code is an ancestor of the other. It also limits same-code targets to lines of the same code.
   - Measured on all touch_round rows:
     - 0 side→side edges cross mains (all 14,698 share a watershed_key);
     - 0 main edges go to a sibling tributary.
   - Round timing could make a line take a worse target only because the better one was not yet
     attached. Comparing each chosen parent with the best touch that ended up attached:
     - 3 mains took P's side channel instead of P. In all 3, the side channel's path enters P next
       (P itself was deferred and attached in the same round). All 3 have 0 outlets. Right.
     - 2 sides differ only by a tie on gap. Right.

4. **Pathless side channels (2,502): mostly right, one material wrong case (Seton / Cayoosh).**
   - 614 belong to mains with no path:
     - 73 are top level, for example a Stikine braid cluster whose mouths dangle at the Alaska
       border;
     - 541 are under mains that leave BC.
     - Right.
   - 1,888 belong to mains that have a path:
     - 748 have mouths that touch nothing within 1 m;
     - 679 touch only a tributary of their main (a descendant code);
     - 774 touch only an unrelated code;
     - 252 touch only unattached same-code braids (closed clusters).
   - Behind all 2,502 there are 7,984 lines, 21,000 segments and 7,204 km. 23 of those segments
     have discharge.
   - 5 placed outlets sit there. All are coastal roots with q_acc = PCIC. Right.
   - Rank-1 candidates behind pathless sides: 66 are broken_chain (was 352) and 9 are demoted.
     Of the 66:
     - 1 is the top-level Stikine braid (48 m3/s), which leaves BC. Right.
     - 54 are behind 3 dangling side channels whose main has a path. Wrong:
       - **Seton side channel 355995374 (edge_type 1350, 100.233886): wrong.**
         - Its mouth touches nothing within 100 m. It is 619 m from the Seton River and 654 m from
           the Fraser.
         - Cayoosh Creek 356364387 and 6 other lines attach to it by 'touch'. Cayoosh has no Seton
           segment with its localcode, so it has no code junction.
         - Result: 3,341 lines without a path to the sea, 49 broken_chain outlets (up to
           17.06 m3/s), and 0 of 7,560 Cayoosh-basin segments with discharge.
         - Water there reaches the Fraser in BC. Round 5 named this case and it is still lost.
       - CLRH 356365484: 4 broken outlets, 3.9 m3/s.
     - 11 are behind 7 sides that touch other lines: INKR, Manson, EUCL, Hatdudatehl, Goldie and
       Shaman (each at most 2.41 m3/s), and Vernon Creek (OKAN). Vernon Creek leaves BC, so it is
       right.
   - The header at lines 28-32 describes rule-5 lines as lines leaving BC or with no BC parent
     code. That is not true of the 1,888.

5. **Deferred code junctions: right.**
   - 14,972 deferred mains attached through rounds, and 37 fell back to code_deferred.
   - Where the deferred main enters its expected parent P, compared with the code junction (cj):
     - within 100 m: 13,258;
     - more than 100 m downstream: 1,552 (252 of them more than 1 km). This is the intended
       Birkenhead correction.
     - more than 100 m upstream: 1. That is 359388226, whose mouth touches P itself at 1,801 while
       its cj is at 228. It has 0 outlets on it or on P.
     - **0 deferred mains enter P upstream of the code junction through a side channel.** There
       are no wrong-direction cases.
   - 279 placed outlets on P lie between the entry point and the cj:
     - 268 (96%) are within 5% of PCIC;
     - 0 are low;
     - 11 are high.
   - The 11 high outlets are not from deferral. They are PCIC siblings stacked at one confluence
     on the main (5019878/9, 5020465/6, 8010661/2, 8011019/20/33/34, 5021187). The excess is the
     sibling's main-stem flow (for example 5021187 has 146.4 m3/s against PCIC's 0.86), not the
     deferred tributary.
   - Round 5 found 23 high and 0 low among 205 outlets under the old rule 1.
   - 161 deferred mains have a path that never touches P. Their P-side channel exits straight
     into a lower code: 127 to the grandparent main or lower, 34 through further side channels.
     - None has a placed outlet on it or upstream of it (0 of 382 lines).
     - All 21 placed outlets on P below their cj match PCIC exactly.
     - This follows the FWA geometry (distributaries at P's mouth). Right.
   - 37 code_deferred: their touched P-side channel has no path. 0 outlets on them. The cj
     fallback is right.

6. **The QA tests (qa.sql:77-85): neither passes vacuously.**
   - The Okanagan test is guarded by `EXISTS (any path)`. 356570548 is the Okanagan River
     (300.432687).
   - The Kitsumkalum test needs a row whose path contains the Skeena 360887278, so an empty table
     fails it. It does exercise rounds (braid 360222215 is round 1).
   - Neither test covers deferral (the Birkenhead fix) or the cycle hazard. That is a gap, not a
     defect.

Note (pre-existing, outside this fix): one duplicate-main code. The `mains` CTE picks 359024601
over the Beaver River 359572098 as the expected parent of 200.692231.387879.* lines. 82 Beaver
tributaries attach by touch anyway, and 2 by code to 359024601. No measurable effect.

## Findings

- **[severity: fragile]** extras/pcic_crosswalk/sql/pcic_crosswalk01_paths.sql:34-38, 173-179 —
  The acyclicity argument is false as written.
  - A rule-2 side→own-main edge sits at round 0 while that main is still unattached (deferred, or
    no code junction).
  - Rule 3 lets a main take a same-code round edge to that braid. touched_depth DESC prefers the
    braid over the parent's side channel. The result is the cycle X → B → X.
  - There are 0 such mains in the current data, and the DO block at lines 226-236 turns any cycle
    into an aborted build. A future FWA load with a braid rejoining exactly at a deferred or
    transboundary main's mouth would fail the job.
  - Fix: restrict same-code round targets to side-channel sources
    (`AND (NOT t.same_code OR NOT b.is_main)`), and state the real invariant in the header: every
    edge goes to an ancestor-or-equal code; same-code edges come only from side channels, to an
    earlier-inserted line or to their own main; mains leave their code.
  - This drops the one Beaver duplicate edge (359024601, 0 outlets). It would fall back to its
    code junction.
- **[severity: bug]** extras/pcic_crosswalk/sql/pcic_crosswalk01_paths.sql:28-32, 163-192 —
  Rule 5 leaves 1,888 side channels without a path even though their main stem has one. The
  header says such lines leave BC or have no BC parent code.
  - Most carry nothing, but Seton side channel 355995374 has a mouth that dangles 619 m from the
    Seton River. Cayoosh Creek (356364387) and 3,340 other lines drain through it.
  - Result: 49 PCIC outlets broken_chain (up to 17 m3/s), and 0 of 7,560 Cayoosh-basin segments
    with discharge.
  - In total, 65 broken_chain rank-1 outlets sit behind pathless sides whose main has a path.
  - Fix: fall back for a side channel whose watershed_key has a path but which has none itself.
    Options are a distance-bounded projection of its mouth onto its watershed_key, or the main-stem
    segment matching its lowest localcode (an equality, like rule 1). Add a QA test, for example
    "Cayoosh Creek 356364387 has a path to the Fraser 356364114".
