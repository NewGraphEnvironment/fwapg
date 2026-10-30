# Progress — fwa_indexpoint(): an exact distance tie on one stream is broken by row order (#39)

## Session 2026-10-24

- Plan-mode exploration. At the gate: tie rule (upstream segment), two branches, the local fwapg
  left untouched, no upstream post without the user's word
- Plan review (Plan agent): kept the tests on `num_features = 5`; outer sort on the unrounded
  distance (G1); found the old measure at 08KD006 that `FWA_LocateAlong` cannot place (A1)
- Phase 1 on `indexpoint-tiebreak` (off `upstream/main`): migration and tests, verification 1–3,
  `/code-check` three rounds all clean (two wording notes applied), commit `d955688`, pushed
- The user asked to measure the effect on bcfishpass and bcfishobs: neither calls
  `fwa_indexpoint`; both carry the same tie in their own SQL. The bcfishobs sample is in findings.md
- Created `39-indexpoint-tiebreak` off `origin/newgraph` for the PWF and the cherry-pick
- Next: cherry-pick, the full bcfishobs count, issue edits, PR into newgraph
- bcfishobs full tie count: 7,198 of 307,121 observations (2.34%) on an exact same-stream tie,
  3,464 (1.13%) with differing localcodes; fresh#266 filed; #39 body rewritten to the as-built rule
- Next: archive, PR into newgraph, show the upstream draft (not posted)
