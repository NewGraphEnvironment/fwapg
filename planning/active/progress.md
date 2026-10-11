# Progress — Run blue line paths, PCIC crosswalk and main-flow tree end to end (#13)

## Session 2026-10-10

- Plan-mode exploration — phases approved by user (whole-basin ladder: yes; upstream: 3 stacked branches)
- Created branch `13-run-blue-line-paths-pcic-crosswalk-and-m` off `newgraph`
- Scaffolded PWF baseline from issue #13 with approved phases
- Next: start Phase 1
- Phase 1: PCIC cache and #11 references copied from the #11 build machine; SSNbler 1.1.2 installed; memory measured
- Phase 2: topology QA builds BC's outline once (QA 35 -> 1.5 min, rows identical)
- Phase 3: `ssnbler_check.sh` (serial, memory-capped); reviewed and rewritten (footprint, worker tag, signal cleanup)
- Phase 4: PCIC ran three times: nondeterministic ties found and fixed (user chose upstream segment); tree identical to #11
- Phase 5: LSKE/BULK/FRAN clean; ladder Bulkley/North Thompson/Nechako clean; whole Skeena exposes SSNbler parallel-path quirk
- Phase 6: READMEs and research record runtimes and memory
- Code-check over the branch: 3 rounds, ended by enumeration of the watchdog's exit statuses; fwapg#14 filed
- Phase 7: upstream branches pushed to the fork (blue-line-paths, pcic-crosswalk and mainflow-tree stacked on it); PR drafts in `upstream_pr_*.md`, not posted
- Commits: f0c469e..HEAD
- Next: /planning-archive, PR into newgraph
