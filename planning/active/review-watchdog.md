# Review: 436a4ea (qa_topology.sql, BC outline once) and aaa8acc (ssnbler_check.sh)

Reviewed 2026-10-10. Neither reviewed script was run. The only database access was read-only SELECTs (statement_timeout 60-120 s, each under 5 s). Every probe ran from the scratchpad.

Environment: PostGIS 3.5.2, GEOS 3.9.0 (OverlayNG), PG 17; R 4.5.2; `/bin/bash` is 3.2.57; `/usr/bin/awk` is bwk 20200816.

---

## Part 1: `extras/mainflow_tree/sql/qa_topology.sql:56-58, 102-105`

**Verdict: no mechanism found that changes the answer, beyond a sub-nanometre boundary perturbation that matters only for a circle tangent to BC's edge. Expect the identical 23 rows.**

### Why the predicate is the same in exact arithmetic
- `fwa_bcboundary` is `ST_Dump(ST_Union(fwa_watershed_groups_poly))` (`load/fwa_bcboundary.sql`): 28,001 valid POLYGONs (0 invalid, checked). They are the parts of one valid multipolygon, so their interiors are pairwise disjoint and two parts can touch only at points.
- Old: covers(union of the parts P_i that intersect B, B). Parts that do not intersect B contribute nothing inside B, so this is exactly B ⊆ BC.
- New: covers(union of the subdivided pieces S_j that intersect B, B). The S_j partition ST_Union(all parts) = BC, so this is also B ⊆ BC.
- Holes: one part has 2 rings (the mainland, id 1). Subdividing it keeps the hole (measured below), and a B in or across the hole is uncovered either way.
- Parts that touch at a point: neither version can cover a disc using such a touch. In both versions, coverage depends only on the point set inside B.
- `coalesce(..., false)` when nothing intersects B behaves the same in both.
- Piece selection: GEOS's `ST_Intersects` is exact on the stored coordinates. A piece it rejects is truly disjoint from B and could not have helped cover it.

### What floating point actually does (probed)
Each original polygon was subdivided and the pieces re-unioned (`probe1.sql`, `probe2.sql`, `probe3.sql` in the scratchpad):

| part | pieces | re-union vs original |
|---|---|---|
| 1406 (143k vertices) | 1185 | symdiff area 4.9e-8 m², 395 slivers, every sliver centroid ≤ 2.1e-10 m from the original boundary; 1 ring → 1 ring |
| 7232, 8249, 11739 | 296 / 313 / 316 | symdiff 2.8-4.4e-8 m², all slivers ≤ 2.0e-10 m from the boundary; no interior rings |
| 1 (mainland, 568k vertices, 1 hole) | 4554 | sum of piece areas minus original area = -0.028 m² of 8.9e11 m² (summation rounding); rings 2 → 2, 1 geometry; no non-polygon pieces |

- **No seam gaps.** Re-unioning the pieces leaves no sliver holes along the internal cut lines: ring counts match, and every symdiff sliver sits on the original outer boundary.
- **There is a boundary perturbation.** `ST_Covers(union(pieces), original)` and the reverse are both **false**. The cause is the new vertex created wherever a cut line crosses the coastline or land border: it is rounded slightly off the original segment, so BC's edge picks up kinks of about 1e-10 m, some inward and some outward. This can flip a mouth only if its 50 m circle comes within about 1e-10 m of BC's edge, in either direction. That is effectively zero probability, but it is the one mechanism that exists.
- **Secondary, not observed.** With GEOS 3.9.0, an OverlayNG union that hits a robustness failure falls back to snapping or snap-rounding. That moves vertices further, but still well under a millimetre. It again matters only for a near-tangent circle, and the old per-mouth union carried the same exposure.
- **Optional cheap guard for the Phase 4 diff.** List the orphan mouths where `abs(ST_Distance(mouth, ST_Boundary(bc)) - 50) < 1e-6`. If none exist, the two methods cannot disagree on any mouth, which makes the row diff conclusive rather than lucky.

Non-issue: the `CREATE TEMPORARY TABLE bc_outline` would fail if the script were re-run in the same session. It follows the same pattern as `qa_nodes` and `orphan_mouths`, and `psql -f` opens a new session each time.

---

## Part 2: `extras/mainflow_tree/ssnbler_check.sh`

### F1. HIGH: the cap measures RSS, which on macOS excludes compressed memory, so it fails toward pass under memory pressure. Lines 63, 84.
- `ps -o rss` counts resident pages. On macOS, pages squeezed by the memory compressor (or swapped) leave RSS but still count toward the real footprint.
- **Verified on this machine now:** the existing R process (pid 8295) shows `ps` RSS = 30 MB, while `top` MEM (phys_footprint) = 458 MB, of which CMPRS = 438 MB. `com.apple.Virtualization` (the Docker VM) holds a 112 GB footprint with 82 GB compressed. Compression is already active.
- **Scenario:** in the 39 GB-at-24k-lines regime, R's older pages are compressed as the machine fills. The summed RSS stays well under the cap while the true footprint passes it, which is the fwapg#2 crash the script exists to prevent.
- **Fix:** sum phys_footprint instead.
  - `top -l 1 -stats pid,ppid,mem,command` takes about 0.5 s and gives pid, ppid and footprint (e.g. `458M`, `112G`, which sometimes carry a trailing `+`/`-`; strip that and scale K/M/G).
  - Keep `ps` for the command line, since `top` truncates it, and join the two on pid. `/usr/bin/footprint -p` is an alternative.
  - Consider a second, system-level trip: `sysctl -n kern.memorystatus_level` (read 94 now), `vm.swapusage` used, or `memory_pressure -Q`.

### F2. HIGH: if the script receives TERM or HUP, the EXIT trap releases the lock but leaves R running unwatched. Lines 39-44.
- `cleanup` kills the recorded workers and removes the lock, but never kills `$pid`.
- **Verified by a probe on `/bin/bash` 3.2** (`scratchpad/sigprobe.sh`, same trap and loop shape):
  - `kill -TERM <script>` ran the EXIT trap, and the background `Rscript` kept running with ppid 1.
  - `kill -HUP` gave the same result. HUP is what a closed terminal or a dropped ssh session sends.
  - Also seen: `kill -INT` sent to R itself does kill it, because R installs its own SIGINT handler even though bash ignores INT for async children. So a Ctrl-C to the whole process group is fine; a signal to the script alone is not.
- **Scenario:** `timeout`, a harness kill of the script's pid, or a closed terminal ends the watcher. R carries on with no cap. The lock is gone, so the next `./ssnbler_check.sh` starts a second large network alongside it, which is exactly what the lock comment (line 36) says crashed the machine.
- **Fix:**
  - Set `pid=""` before the trap.
  - In `cleanup`, if `pid` is set and `kill -0 "$pid"` succeeds, `kill "$pid"`, then the current workers, then `wait "$pid"` (with a KILL fallback after a few seconds), and only then `rmdir`.
  - `trap 'exit 129' HUP; trap 'exit 143' TERM; trap 'exit 130' INT` makes the exit status explicit. Bash 3.2 already runs EXIT on these, as verified.

### F3. MEDIUM: the `work[R]SOCK` match counts and kills every PSOCK worker on the machine, not only this run's. Lines 64, 69, 87, 41.
- **Verified that the pattern does match SSNbler's workers.** SSNbler's `get_pdist_nodes` and `get_pdist_rid` each call `makeCluster(ncores)`, PSOCK by default. A live 2-worker probe showed workers as
  `.../bin/exec/R --no-echo --no-restore -e tryCatch(parallel:::.workRSOCK,error=function(e)parallel:::.slaveRSOCK)() --args MASTER=localhost PORT=11662 OUT=/dev/null ... SETUPSTRATEGY=parallel`
  with **ppid 1**: `system(wait = FALSE)` runs them through an `sh` that exits, so they are reparented to launchd. The ancestor walk can never find them, and the pattern match is necessary. `work[R]SOCK` matches `workRSOCK`, and the awk program's own text (`work[R]SOCK`) does not match itself.
- **Verified with a mocked `ps` input through the exact awk program:**
  - It also matched an unrelated `vim notes-about-workRSOCK.txt` (pid 950), added its RSS to the total, and returned it in the worker list to be killed.
  - Any other R session's cluster would be treated the same way: RStudio, another pipeline, or another user, since `ps -ax` shows every user.
  - None are running right now (0 matches).
- **Scenario:** a user's RStudio holds a 4-worker cluster of 8 GB each. A small SSNbler run exceeds the cap because of those workers, gets killed with exit 3, and the RStudio workers are killed too. Separately, `peak_rss_gb` in `runs.log` is inflated.
- **Fix:** tag this run's workers. In `ssnbler_check.R`, before `lines_to_lsn`, call
  `parallel::setDefaultClusterOptions(outfile = file.path(normalizePath(args[2], mustWork = FALSE), "workers.log"))`.
  SSNbler's bare `makeCluster(ncores)` picks this up through `addClusterOptions(defaultClusterOptions, ...)`. The worker command line then carries `OUT=<abs lsn dir>/workers.log`, so the shell can match `OUT=$abs_dir/workers.log`. A side benefit is that worker errors get logged instead of going to /dev/null. Cheaper but weaker: also require each worker's start time (`ps -o lstart=`) to be after `$start`.

### F4. MEDIUM-LOW: stale worker pids are killed without re-checking them. Lines 80-82, 87, 41.
- `$workers` accumulates every worker pid ever seen.
- SSNbler starts and stops two clusters, one per `get_pdist_*` call. After the first cluster's `stopCluster`, those pids are free.
- macOS allocates pids sequentially and wraps at 99999. The watcher alone forks about 4 processes every 3 s.
- **Scenario:** on a long run a stale pid is reused by an unrelated process, which gets SIGTERM at the cap (line 87) or in `cleanup` (line 41).
- **Fix:**
  - At the cap, kill only the workers in the *current* sample (`$new`).
  - In `cleanup`, re-verify each pid's command line (`ps -o command= -p "$w" | grep -q "<tag>"`) before killing it.

### F5. MEDIUM: a failed sample silently disables the cap. Lines 63-72, 79, 83-84.
- awk's `END` always prints `t + 0`. If `ps` fails, is restricted (for example inside a sandbox), or R is missing from its output, `sample` prints `0`, the cap never fires, and nothing says so.
- **Verified on bash 3.2:** under `set -euo pipefail`, `read -r a b <<< "$(false | awk 'END{print 0}')"` gives `a=0` and the script continues. The pipefail status of the substitution never reaches `set -e`.
- If `kb` were ever empty, the `[ ... -gt ... ]` tests print "integer expression expected" and evaluate false. Lines 83 and 84 sit in `&&` and `if` contexts, so `set -e` does not abort there either.
- The good news, answering the question asked: nothing in the loop can abort the script under `set -e` and leave R running unwatched. The loop's failure mode is the opposite one, silent and toward pass.
- **Fix:**
  - Have awk print a sentinel when `root` is absent from the table (`if (!(root in p)) { print "ERR"; exit }`).
  - In the loop, treat `ERR`, a non-numeric value, or `0` while `kill -0 "$pid"` succeeds as a watchdog failure: log it, kill R, and exit non-zero (or retry once).

### F6. LOW: no SIGKILL escalation at the cap. Lines 87, 93.
- The script sends `kill` (TERM) and then waits indefinitely.
- Probed: R died on TERM during `Sys.sleep`. R installs no TERM handler, so the default action should also kill it inside C code, but that was not probed.
- **Fix:** after TERM, poll `kill -0` for about 10 s, then `kill -9`.

### F7. LOW: a stale lock after SIGKILL, a crash or a reboot blocks every later run. Line 37.
- The lock fails closed, which is the safe direction, but the refusal message gives no remedy. The case that leaves it behind is the machine crash the lock exists for.
- **Fix:** write `$$` into `$dir/.lock/pid`. On refusal, print it and say "remove with `rmdir`/`rm -r` if that pid is not running", or reclaim the lock automatically when `kill -0` on that pid fails.
- Note: the lock serialises only this driver. The README's manual `Rscript ssnbler_check.R` path bypasses it.

### F8. LOW / INFO: sampling and accounting
- Sampling every 3 s means the cap needs headroom of at least the growth over about 3.5 s (the sample plus `top`'s 0.5 s if F1 is adopted) plus kill latency.
- Summed RSS counts libR's shared pages once per process. That overcounts, which is the safe direction, by roughly 50-80 MB per worker.

### F9. INFO: the awk ancestor walk is correct and terminates. Line 68.
- The walk stops on `""` (parent not in the snapshot), `0` (`kernel_task`, which is its own parent), `1` or `root`. A single `ps` snapshot cannot contain a cycle other than pid 0 → 0, which is handled.
- **Verified with mocked input:** R, its `sh` child and grandchild, and the reparented worker were all summed (1000+50+70+2000), and an orphan whose parent was missing ended the walk cleanly.
- String/number comparisons work in bwk awk, because keys carry no leading spaces or zeros.
- Nit: reading `p[x]` for a missing parent inserts a new element while `for (q in p)` is iterating. In bwk awk that can rehash mid-iteration, so at worst a process is visited twice or skipped. Guard it with `while ((x in p) && x != 0 && x != 1 && x != root) x = p[x]` and then test `x == root`.

### F10. INFO: bash 3.2 compatibility. No problems found.
- The constructs used all work in 3.2: unquoted `=~` with ERE `{0,3}`, `<<<`, `${4:--}`, `local`, `$(( ))` (64-bit), and `set -u` on variables that are defined but empty (`$outlets`, `$workers`, `$new`).
- No arrays, so the empty-array `set -u` trap does not apply. The probes above ran on `/bin/bash` 3.2.57.
- Minor: `PG:"$DATABASE_URL"` puts the connection string, password included, in `ps` output (local default credentials here).

## Probe files (scratchpad)
`probe1.sql`, `probe2.sql`, `probe3.sql` (read-only subdivide/re-union checks); `sigprobe.sh` (trap and signal behaviour); `fakeps.txt` (mocked input for the awk walk).
