## Outcome
Fixed SSNbler 1.1.2's false topology errors on a fork, NewGraphEnvironment/SSNbler, branch `fix-pdist-precision-parallel-unsnapped` at **37ca338** (based on upstream `develop`), and re-ran the main-flow tree's SSNbler check against it. Every run is now clean. The fork has three fixes plus tests that fail on 1.1.2:

1. **Double-precision distances.** All five `pdist::pdist()` calls were replaced by an internal `dist_xy()` that subtracts first, and pdist was dropped.
2. **Chunk offsets on the parallel path.** Chunks return zero-distance pairs, and `combine_node_chunks()` offsets them by the real chunk sizes before counting duplicates.
3. **`split_matrix(drop = FALSE)`.**

What was learned:

- **The precision fix changed at the plan gate.** The issue prescribed an origin shift. Measured, pdist's error grows in proportion to the coordinates, so a shift only narrows it to the data's own extent. The user chose exact distances.
- **The mechanism was wrong twice.** The cause is not cancellation: pdist rounds every coordinate to single precision (`as.single()`, C `float`). Whether a given pair reads 0 is therefore a coincidence of position, not a threshold. Three review rounds corrected the wording of NEWS and the commit messages twice, because each figure written was a value seen at one configuration and stated as a constant. It ended by enumerating every factual claim, and the NEWS entry now states the mechanism with no ranges.
- **The parallel defect cannot fire on its own.** Once distances are exact, nodes are deduplicated, so no end is ever at distance 0 from two of them. Its fix is tested on the combiner directly. The plan review caught this, and also caught that PSOCK workers load the *installed* package, so parallel tests and mutants must be installed (`R_LIBS`) to mean anything.

On the fwapg side, `ssnbler_check.R` now prints the SSNbler build and its source, and fails on edge relationships that split or miss edges. The README installs the fork with `pak::pak("NewGraphEnvironment/SSNbler@37ca338")`. The issue body was edited to match what was built. The upstream PR, drafted in `upstream_pr_draft.md` and approved by the user, is pet221/SSNbler#9 (base `develop`, 2026-10-11). The user opened it by hand, because auto mode blocks posting to a repo outside the org. Checking every watershed group on the fork is #19. Switching back to CRAN is a separate issue, to be filed once upstream releases a fix. Durable findings are in `research/fwa_mainflow_tree.md`.

## Measurement
- **pdist error against coordinate magnitude** (2,000 random pairs each, pdist 1.2.1):
  - 0.1 mm at 10³ m, 0.9 mm at 10⁴, 9 mm at 10⁵, 1.6 cm at 2×10⁵, 3.3 cm at 4×10⁵, 6.4 cm at 10⁶
  - identical points are always exactly 0

  This turned "origin shift" into "exact distances".
- **Fork tests:** 188 pass (157 upstream + 31 new).
  - The new ones fail on 1.1.2 (10 failures).
  - Each fix reverted alone makes at least one fail: precision 8, offsets 1, drop 1.
  - `R CMD check --as-cran`: 0 errors, 0 warnings, 1 NOTE (the `.9000` version).
  - MF_streams (EPSG:5070) outputs are byte-identical before and after, on both paths.
- **Acceptance, fork against 1.1.2:**

  | Run | Path | Lines | Fork | 1.1.2 |
  |---|---|---|---|---|
  | USKE | serial | 21,655 | 0 errors, 17-18 GB | 4 errors, 28 GB |
  | MSKE | serial | 24,732 | 0 errors, 24-28 GB | 4 errors, 37 GB |
  | Skeena | parallel | 261,764 | 0 errors, 1 outlet, 261,763 relationships with none splitting; 10.9 GB, **54 min** | 6 errors, 19.9 GB, 35 min |
  | Bulkley | parallel | 52,293 | outputs byte-identical to 1.1.2; 3.8 GB | 3.5 GB |

  The issue's shift test, with no shift, gives 0 and 0. The reprex is clean. The parallel path is slower because `dist_xy()` runs in R where pdist ran in C; this is stated in the PR draft.
- **Wrong turns kept:**
  - The first `rcmdcheck` reported 0/0/0 on a check that had *halted* at a CRAN `archive.rds` timeout.
  - A file-based waiter fired on a review's first bytes.
  - The `st_line_sample()` end-point drift (1 ulp on long lines) was chased and not reproducible as an error in 41,500 cases (40,000 synthetic lines, 1,500 shifted real ones). It was left unchanged and noted in the PR draft.
  - The build label went from "local" to "standard" to "CRAN" across two review rounds. That loop ended by enumerating every (RemoteType, Repository) pair in the library.
- **Review spend:** 6 agents in total: the plan review, 3 rounds on the fork and 2 on the fwapg branch.

## Evidence
Local and gitignored:

- `extras/mainflow_tree/data/ssnbler/runs.log`: the lines from 2026-10-10 23:15 onwards, local time, carry an `ssnbler:` build field
- `extras/mainflow_tree/data/ssnbler/{grp_skeena_USKE,grp_skeena_MSKE,basin_skeena,basin_bulkley}.log`

Fork:

- `git -C ~/Projects/repo/SSNbler log d3918f1..37ca338`

Closed by: PR into `newgraph` (branch `16-fix-ssnbler-s-false-topology-errors-on-a`)
