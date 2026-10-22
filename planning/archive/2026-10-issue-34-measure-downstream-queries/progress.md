# Progress — Measure downstream queries: ltree, blue line path arrays, and a downstream_id from the main-flow tree (#34)

## Session 2026-10-21

- Fast-forwarded `newgraph` (two CLAUDE.md sync commits) and `main` to their remotes before exploring
- Plan-mode exploration: two Explore sweeps (mechanisms; repo conventions), direct reads of the paths, tree and trace SQL, probes on the local database (sizes, Hope, five random origins, 200-origin chain lengths, the edge cases of the pointer rules)
- One decision taken at the plan gate: `downstream_id` for every segment in its own lookup table
- Phases approved by user; a Plan-agent critique (24 findings, `review-plan.md`) folded into the plan before the baseline
- Plan parked in the issue body under `## Plan`
- Created branch `34-measure-downstream-queries-ltree-blue-li` off `newgraph`
- Scaffolded PWF baseline from issue #34 with approved phases
- Commits: 43d13ea (baseline)
- Session ended after the baseline by `/compact-prep`; nothing of Phase 1 started
- Next: start Phase 1 (`scripts/bench.sh`, `sql/00_env.sql`, `sql/00_origins.sql`) against the local Docker database (`DATABASE_URL` exported); re-read the plan in the issue body first

## Session 2026-10-21 (resumed after /clear)

- Phase 1: `scripts/bench.sh` (one psql call per step and cell, URL redacted, timeouts recorded per cell), `sql/00_env.sql`, `sql/00_origins.sql`, `sql/00_hope.sql`, `sql/06_timings.sql` (timing tables and the cell matrix as `fwapg.bench_cells`)
- Env: assertions hold; new fact, 158,188 on-network segments with a null local code (findings)
- Origins: 100,000 random and every eligible segment of ADMS, BULK, LFRA (2 min)
- Hope trace warm: median 953 ms on the idle server (the 6.8 s probe was cold). A first run gave 1,085 ms under an orphaned 26 h `pcic` QA query holding 7 cores; that query (no client left) was cancelled, and bench.sh now waits for an idle server before each timed step
- Phase 2: paths re-timed (992 s, md5s identical before and after); `fwapg.downstream_ids` built in 142 s, 385 MB, QA all `t`; rule 3 steps past a parent that starts at the junction (249 segments)
- bench.sh: body wrapped in `main` after an edit landed while a run of it was in flight (bash reads scripts as it runs)
- Phase 3 harness: walk files 02–04, `05_explain.sql`; the sink pre-extended after the first EXPLAINs showed inserts into new pages cost 4 s of A's 5.6 s at 1,000 origins (Docker Desktop host mount)
- Phase 4 run before the timings (it would load the server under them): `07_results.sql`, `07_compare.sql`, `07_setdiff.sql`; three iterations of the classes (`logs/compare_*`), the last with nothing unattributed; Hope fixture holds at 161.40 km, the docs' 308.54 km is stale (309.70 km verbatim)
- Plan correction: cells time the walk under an aggregate over every column, not an INSERT (PostgreSQL never parallelises a data-modifying statement, which would have made the no-parallel pass a repeat); EXPLAINs re-run
- Timing matrix launched 2026-10-21 17:16 UTC (`bench.sh timings`, defaults then noparallel)
- Timing matrix finished 2026-10-21 21:25 UTC (defaults 17:16–19:18, no-parallel 19:18–21:25); only A-pred at 1,000 timed out (both passes)
- Review round 1 (11 findings): dispatch query moved out of the timed interval (cells 0, 1 and L1 1,000 re-run, with a no-origin cell for the fixed cost); classes tightened (side channels non-main, route_differs must rejoin, path_ends must be a prefix), which exposed 15,188 main-line segments now attributed to `path_ends` and `code_parent_bypassed`; results regenerated with the final walk files; home paths redacted from logs
- Review round 2 (9 findings): settings confounded with time, so 11 cells re-run interleaved (A B B A, 22:08–23:16 UTC) with P as the drift control; `path_ends` restricted to main lines; comparative claims rewritten from the logged ratio table and enumerated (findings, "Claims checked")
- Review round 3 (11 findings, the same mechanism: claims checked as re-stated, settings effects generalised from interleaved cells): research Speed and Answers rewritten with each sentence scoped to named cells and settings, an arrays-over-pointers table added; Hope 0.32 km re-attributed to two segments absent from `fwa_streams`; claims table rebuilt against the sentences as written
- Review round 4 (a first attempt stopped on the account spend limit; the retry, `review-round4b.md`) enumerated 141 claims (107 research, 34 comment draft) against the logs and the database: no defect inside a round-3 fix; 12 corrections (1,208 local-code order pairs, not 1,242; 158,188 null local codes outside 999; the tree's cost stated; 3.8 not 3.7; comment wording) and one more home path, in `ab_run_*.out`, redacted. The loop ends on that enumeration
