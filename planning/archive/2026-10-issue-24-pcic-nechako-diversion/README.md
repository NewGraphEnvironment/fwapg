# PCIC crosswalk: Nechako Reservoir outlets unplaced (#24)

## Outcome

PCIC drains the Nechako Reservoir through the Skins Lake spillway and the Cheslatta, and the FWA drains it down Knewstubb Lake into the Nechako canyon. Placement keeps PCIC's chain on the FWA, so PCIC's single reservoir outlet 1007550 landed on the spillway line, which the FWA does not connect to the reservoir. Nothing above it could place: 479 outlets were `broken_chain`, and the reservoir's FWA segments read about 0 m³/s (wet#57). The crosswalk now takes a hand-listed **diversion** (`sql/pcic_crosswalk03_diversions.sql`, one row). The listed outlet is placed at the lake's FWA exit. It has two parents: its *position parent* (1002307 in the canyon, kept in `fwapg.pcic_qa_diversions`) loses its area, and its *flow parent*, published as `fwa_parent_subid` (1008709 at the spillway), receives its water. The gate chose PCIC's spillway route, so the canyon carries only its own runoff, as in PCIC. Taking `fwa_parent_subid` as the flow parent was the default, named in the PR. Both reference runs were rebuilt on crosswalk 901d1271, published to fresh-bc and read back. The other large clusters of unplaced outlets are #46. The durable verdict is in [`research/pcic_crosswalk_diversions.md`](../../../research/pcic_crosswalk_diversions.md).

## Measurement

- **Baseline** (crosswalk b1a71083, 1951-2012):
  - placed in LEUT / UEUT / UNRS / LNRS: 0/72, 0/203, 1/111, 3/101;
  - median specific runoff 0.2-0.3 mm/yr;
  - the Knewstubb exit 0.134 m³/s, where PCIC has 156.4;
  - gauges 08JA015 / 08JA016 / 08JA028 at 0.001 / 0.001 / 0.024 against PCIC's 3.905 / 0.684 / 44.962.
- **After, 1951-2012:**
  - placed 72/72, 199/203 (the 4 have no candidate), 111/111, 101/101;
  - median 353.1, 353.5, 385.9 and 144.1 mm/yr;
  - segments under 5 mm/yr 0.1-0.4% (were 97-100%);
  - the exit 156.365 against PCIC's 156.366;
  - those three gauges equal PCIC;
  - 08JA013 and 08JA017 unchanged (PCIC is 1.64 and 2.21 times observed: no Kemano in PCIC's model).
  - 1981-2010 gives the same picture: the exit 155.832 against 155.832.
- **Province-wide:**
  - qa_report moved only by the 479 outlets going from broken_chain to placed;
  - gauges within 10% of PCIC at 497 of 538 (was 494) for 1951-2012, and 404 of 431 (was 401) for 1981-2010;
  - drainage flags 218 `small` / 127 `big` (were 218 / 126), with 1008709, 1001496 and the Cheslatta's mouth `big` by design (README caveat);
  - following 248 / 188.
- **Outside 1007550's subtree** (`compare_published.sh`, both periods, against the published files):
  - crosswalk rows and sub-basin days unchanged;
  - one segment weight moved: a reservoir tributary's top in CHIL;
  - 119-1,204 weights differ only in `upstream_subids` order (07's `array_agg` has no ORDER BY).
- **Clamps:** segment-months clamped at zero rose from 0.943% to 1.041%. All of the rise is inside the five groups, the newly placed lakes' freshet; outside them the zero rows are identical.
- **QA proved by mutation:**
  - M1-M5 on a held dev build each turned the intended test `f`;
  - the area test, run against three wrong area statements on a scratch schema, read `t` on 06's and `f` on each.
- **Timings:**
  - dev build (monthly) 36 min 41 s;
  - rebuild 1 (1981-2010, weekly) 4 h 13 min;
  - rebuild 2 (1951-2012, per-year days) 3 h 45 min;
  - upload of 73 objects 26 min 15 s;
  - load from fresh-bc 33 min 25 s;
  - 1983 over HTTP 19.1 s.
- **Review spend:** five agents (the plan review and four `/code-check` rounds), which is the per-task bound. Round 3 found a defect inside round 2's fix, and the review ended on an enumeration of the mechanism's 20 rows. The scripts under `logs/` were not agent-reviewed.

### Wrong turns kept

- Dev build 1 stopped at step 3. An `UPDATE ... FROM x, LATERAL (...)` cannot see the target table. The exit is now derived in a subquery.
- The first area test checked the flow parent by the diversion being larger, which is a proxy (round 2). Its fix checked only that side. Round 3 found the other half missing, and the test now checks both parents by definition.
- The weights comparison first showed 1,205 changed segments outside the groups. 1,204 were array order only; one was real.
- 08KH006 (Quesnel near Quesnel) reads FWA 0.276 against PCIC 221. The previous build has the same value, so it predates this branch and was left alone.

## Evidence

`logs/20261027_*`: the baseline, both builds' traces (database URL and temp paths scrubbed), the Nechako measurements, gauges, the published-files comparisons, the mutation checks and the read-back. The scripts that produced them are `logs/*.sh` and `logs/nechako_measure.sql`. The HTTP read-back used #42's `readback_http.R`. Review rounds are in `review-*.md`.

## Owed

- Close #24 by hand, with a comment naming the PR (a merge into `newgraph` does not close it).

Closed by: PR into `newgraph` (opened from this branch after this commit); issue #24 closed by hand after its merge.
