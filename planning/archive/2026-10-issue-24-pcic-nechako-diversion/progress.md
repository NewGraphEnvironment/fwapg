# Progress — PCIC crosswalk: Nechako Reservoir outlets unplaced (#24)

## Session 2026-10-27

- Plan-mode exploration on the local build (crosswalk b1a71083): measured the reservoir case, the gauges and the other broken-chain clusters; gate decisions taken by the user (spillway route; rebuild and publish on the branch)
- Phases approved by user
- Created branch `24-pcic-crosswalk-nechako-reservoir-outlets` off `newgraph`
- Scaffolded PWF baseline from issue #24 with approved phases
- Next: start Phase 1
- Filed #46: the next-largest clusters of unplaced outlets (Phase 7)
- Dev build (held staging) started 15:19Z from a scratch worktree at 46fcf91, for the mutation checks
- Plan review delivered (review-plan.md): no design blocker; export refusal on the first rebuild (fixed in the plan); refusals for a missing position parent, a doubled route and an unowned receiving segment added to 06; the diversions kept as fwapg.pcic_qa_diversions; two more QA tests (one segment per diversion, Eutsuk 1001917)
- Dev build 1 failed at 03_diversions (findings, Errors); fixed and probed on its staging; dev build 2 relaunched
- Dev build 2 passed every QA test (36 min 41 s); mutation checks M1-M5 each caught by the intended test
- Deleted the old crosswalk's 1951-2012 rows from pcic.* before rebuild 1 (plan review 1)
- Code check rounds 1-4 (findings: Code check); ended by enumeration
- Rebuild 1 (1981-2010, weekly) passed QA and exported, 4 h 13 min; measured, gauges, area test re-proved by mutation, pcic_test.sh passes (findings: Rebuild 1)
- Phase 4: README refusal sentence tightened to the code's refusals (round 4), Nechako caveat; research/pcic_crosswalk_diversions.md and its index row. Rebuild 2 (1951-2012, DAYS=1) started 21:01:34Z at 26d7582
- Rebuild 2 (1951-2012, DAYS=1) finished 00:46:44Z, 3 h 45 min: QA all t, same crosswalk fingerprint, 63 per-year files rewritten. Measured (findings: Rebuild 2); README counts updated
- Published: 73 objects to fresh-bc in 26 min 15 s, sizes match; 1983 read back over HTTP; loads from fresh-bc into a scratch database pass (findings: Publish and read back)
- Opened PR #47 into newgraph; commented on wet#57 with the numbers
