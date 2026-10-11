# Task: Run blue line paths, PCIC crosswalk and main-flow tree end to end (#13)

**If we do it:** the three extras jobs on `newgraph` (`blue_line_paths`, `pcic_crosswalk`, `mainflow_tree`) have each run end to end in their committed form, and are ready to be cut into upstream PRs. **If we don't:** they go upstream having been read but never run as scripts. In #2 every SQL file ran, but piece by piece, so the scripts' shell parts never did. `pcic_crosswalk.sh` has not run in full since the blue line paths moved out of it.

## Phase 1: Set up the run machine
- [x] rsync the #11 build machine's `extras/pcic_crosswalk/data/` to the same path on the run machine (gitignored, reused rather than downloaded again)
- [x] Copy the #11 build machine's #11 outputs to `extras/*/data/ref_11/` (gitignored) as the comparison reference: the three `*.csv.gz` files, `qa_topology.csv`, `qa_drainage.csv`
- [x] Install SSNbler 1.1.2 on the run machine, the same version as the #11 build (a change to the machine, stated here)
- [x] Record free memory with the DB running (`vm_stat` / `memory_pressure`) → this sets the watchdog cap

## Phase 2: Topology QA, BC outline built once (`extras/mainflow_tree/sql/qa_topology.sql`)
- [x] Build a temp `bc_outline`: `ST_Subdivide(ST_Union(fwa_bcboundary.geom))`, GiST-indexed, analyzed
- [x] The `no_parent` test covers each mouth's 50 m buffer with the union of only the subdivided pieces it intersects. The semantics are unchanged; it is only faster.
- [x] Update the comment and the README's runtime note. The check is that the rows match exactly, not just the count; it is verified in Phase 4.

## Phase 3: SSNbler driver with a memory watchdog (`extras/mainflow_tree/ssnbler_check.sh`, committed)
- [x] `ssnbler_check.sh <cap_gb> <name> <wscode> [group] [expected outlets]`: exports the tree subset to `data/ssnbler/<name>.gpkg` (the README's ogr2ogr recipe), then runs `ssnbler_check.R` and kills it above the cap
- [x] The watchdog sums RSS over the R process **and its children**, because the parallel path (≥ 46,340 lines) forks workers that a master-only sample misses. It logs peak RSS, wall time, lines, node errors and outlets in one line per run.
- [x] Runs one at a time, enforced by a lock file, so two checks are never in memory together
- [x] Add a README section with usage. An exit status other than 0 (a kill, or an error from R) fails loudly.

## Phase 4: Run the pipelines (never two at once; both rebuild the shared paths)
- [x] `extras/pcic_crosswalk/pcic_crosswalk.sh`, log under `data/`. Expect: blue line paths QA 3/3, crosswalk QA 10/10, `pcic_fwa_crosswalk` 48,716 rows, `fwa_stream_networks_discharge_monthly` 40,524,612 rows, sum(round(q_m3s,6)) = 178169881.209890
- [x] Compare against `ref_11`: run `zcat | sort | md5` on each export and diff `qa_drainage.csv`. Any difference is investigated, not explained away.
- [x] `extras/mainflow_tree/mainflow_tree.sh` (it calls `blue_line_paths.sh` again). Expect 4,510,368 segments and QA 10/10 (0 splits, 8 cut-offs, 473 dead ends, 23 `no_parent`)
- [x] Diff the tree export and `qa_topology.csv` against `ref_11`: the rows must be identical, which confirms the Phase 2 change
- [x] Record each stage's runtime from the logs (paths, crosswalk stages, tree, topology QA)
- [x] Fix anything that breaks in the scripts as committed. A fix is committed and the job rerun from the top.

## Phase 5: SSNbler groups, one at a time
- [x] LSKE, BULK and FRAN whole (Skeena `400` / Nechako `100.567134` share), with peak RSS and runtime per group
- [x] Rerun the USKE and MSKE spots to confirm the #2 results reproduce on the run machine
- [ ] Ladder, which stops at the first rung over the cap: about 50k lines, about 100k lines, then the Nechako whole (about 210k lines). Rung subsets are picked by wscode and counted in SQL first. The goal is to measure the memory, and whether the parallel path works above 46,340 lines.

## Phase 6: Record
- [ ] `extras/mainflow_tree/README.md`: LSKE/BULK/FRAN results, the ladder's memory curve, the new topology QA runtime. The machine is described by its capacity only (128 GB, local Docker database), with no host names.
- [x] `extras/blue_line_paths/README.md` and `extras/pcic_crosswalk/README.md`: measured runtimes, plus a note that the full script ran
- [ ] `research/fwa_mainflow_tree.md`: revise the SSNbler memory finding with the measured curve (update the `Verified:` line)

## Phase 7: Upstream branches (drafted, not posted)
- [ ] `upstream-blue-line-paths` off `upstream/main`: `git checkout newgraph -- extras/blue_line_paths`, plus its entry in `extras/README.md`
- [ ] `upstream-pcic-crosswalk` on top of it: `extras/pcic_crosswalk` with the issue references stripped
- [ ] `upstream-mainflow-tree` on top of the blue-line-paths branch: `extras/mainflow_tree` stripped the same way
- [ ] On each branch, grep for leftovers (`NewGraphEnvironment`, `fwapg#`, `fresh-bc`, `planning/`, `CLAUDE.md`, `research/`) → expect none
- [ ] Push the three branches to `origin` (our fork). Write the PR bodies to `planning/active/upstream_pr_*.md`. **Nothing is opened on smnorris/fwapg** until it is approved.

## Validation

- [ ] All three scripts ran in their committed form; outputs identical to #11 (sorted md5 match)
- [ ] Topology QA runtime measured after the BC-outline change; 23 `no_parent` rows identical
- [ ] SSNbler LSKE/BULK/FRAN + ladder recorded in `extras/mainflow_tree/README.md`
- [ ] Tests pass
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Host: the run machine is described in the private host issue, never in this public repo.
`DATABASE_URL=postgresql://postgres:postgres@localhost:5432/fwapg` (local Docker default).
