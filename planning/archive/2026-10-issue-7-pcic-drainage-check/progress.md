# Progress — PCIC crosswalk: drainage check at every placed outlet (#7)

## Session 2026-10-08

- Plan-mode exploration — phases approved by user
- Created branch `7-pcic-crosswalk-drainage-check-at-every-p` off `newgraph`
- Scaffolded PWF baseline from issue #7 with approved phases
- Next: start Phase 1 (rebuild staging from cache)
- Phase 1: staging rebuilt from cache (37,667 placed, identical to the #5 final build). Density proxy headwater-biased; added a runoff proxy; flag only when both agree; restricted to main stems (side channels get the main river's area from the lookup).
- Phase 2: seeded errors caught (Nicola on Clapperton; 200/200 small→10× area; 198/200 big→1/10 area). 82/85 over-10× outlets flagged small.
- Phase 3: `sql/qa_drainage.sql` (table `fwapg.pcic_qa_drainage`, report), wired into step 5 before qa.sql, exported to `data/qa_drainage.csv`; qa.sql ceiling test (≤ 300 small, ≤ 200 big; measured 218/124); README section.
- Code-check: 3 rounds (R1 2 fragile fixed + small-group fallback; R2 clean; R3 enumeration, 1 fixed: lake-only subtrees judged by runoff). Final 218 small / 126 big / 0 unmeasured; all 13 QA tests pass.
