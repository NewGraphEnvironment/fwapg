# Code-check round 3 (#13): exit-status mechanism in ssnbler_check.sh

Reviewed `extras/mainflow_tree/ssnbler_check.sh` at fbde58f. I checked every claim below that changes a verdict
on macOS `/bin/bash` 3.2.57, running a scratch copy with stub `ogr2ogr`/`ogrinfo`/`Rscript` on PATH (in
`scratchpad/r3/`). No database writes. The real R script was not run, because nothing here depends on it.

## Mechanism

The header and README define a closed exit-code contract: 0 clean, 1 node errors or outlet mismatch, 2 bad
arguments or a run already going, 3 killed, 4 memory could not be sampled, 5 no result. The script **assumes the
code it exits with is always one it assigned**. In fact, every command not followed by an explicit
`|| exit N` or `|| rc=N` hands the exit code to something that does not speak the contract:

- `set -e` / `pipefail` exit with the failing tool's own status. That is usually 1, which collides with "node
  errors", and it skips the `runs.log` line.
- `set -u` on bash 3.2 under an EXIT trap exits with the previous command's status, often 0 (round 1).
- `wait` passes R's raw status through: 2 from an R fatal error, 127 when Rscript is missing, 128+n when R is
  killed by a signal.
- A failing command inside the EXIT trap, under `set -e`, replaces an `exit N` already in progress with its own
  status. Probe: `set -e; trap 'false' EXIT; exit 3` exits **1**.

Rounds 1 and 2 fixed the instances (the DATABASE_URL check, `|| exit 5` on ogr2ogr, and 1→5 when there is no
result line). The assumption is still in place everywhere else. The full fix is one rule: every exit path either
assigns a contract code explicitly, or maps the passed-through status into the contract before `exit`.

## Enumeration

"Handled" means the code that reaches the caller is a contract code that means what happened.

| line | site | what could be unset or fail | what reaches the caller | verdict |
|---|---|---|---|---|
| 21 | `cd "$(dirname "$0")"` | `cd` fails (substitution status lost) | `set -e`, 1, before the trap | unhandled, negligible (cannot fail in practice) |
| 24-29 | `$1`..`$5` | unset positional | `$#` check runs first; `${4:--}`, `${5:-}` | handled |
| 31-35 | argument regexes | | explicit `exit 2` | handled |
| 38 | `DATABASE_URL` | unset | explicit `exit 2` (round-1 fix) | handled |
| 41 | `mkdir -p "$dir"` | no write permission | `set -e`, **1**, before the trap, no runs.log | unhandled, low |
| 45 | `export WORKER_TAG="…$(pwd -P)…"` | `pwd -P` fails | status masked by `export`; tag loses its prefix, so workers are uncounted | unhandled, negligible |
| 50 | `if ! mkdir "$lock"` | mkdir fails for a reason other than "exists" (permission, `.lock` is a file) | read as a stale lock, then line 58 fails | see 58 |
| 51 | `holder=$(cat … \|\| true)` | | | handled |
| 52-54 | `$holder`, "already running" | | explicit `exit 2`, before the trap, so the other run's lock is kept | handled |
| 58 | `echo $$ > "$lock/pid"` | `$lock` not a writable directory (follows 50) | `set -e`, **1**, before the trap | unhandled, low |
| 61-63 | `workers()`: `ps \| awk` | `ps` fails | output empty; status ignored by every caller | see 68/70 |
| 67 | `$pid` in `stop_run` | unset | initialised at 60, before the trap at 79 | handled |
| 68, 73 | `kill "$pid" $(workers) … \|\| true` | | `\|\| true` | handled |
| 70 | `kill -0 … \|\| [ -n "$(workers)" ] \|\| return 0` | `ps` fails, so it reads as "no workers" | returns early, skipping `kill -9` | unhandled, negligible (`ps` failing) |
| 77 | `rm -rf "$lock"` in `cleanup` (EXIT trap) | fails (permission) | `set -e` in the trap **replaces the in-flight `exit "$rc"` with 1** (probed: `exit 3` became 1) | unhandled, low |
| 79-82 | HUP/INT/TERM traps | | `exit 129/130/143`, then EXIT trap. Probed TERM: 143, lock removed, R killed | handled |
| 79-82 | second signal during `cleanup` | | exits from inside the trap, skipping `rm -rf` and `kill -9`; the stale lock is taken over next run | handled (by takeover) |
| 84-85 | `$wscode`, `$group` | | validated, set | handled |
| 86 | `rm -f "$dir/$name.gpkg"` | fails | `set -e`, 1, no runs.log | unhandled, negligible |
| 87-90 | ogr2ogr | export fails | explicit `exit 5` (round-2 fix) | handled |
| **91** | `n=$(ogrinfo … \| awk …)` | ogrinfo fails | `pipefail` makes the assignment fail; `set -e` exits with **ogrinfo's status (1)** before the `exit 5` guard on 92. No runs.log line | **unhandled. Probed: exit 1** |
| 92 | `[ "${n:-0}" -gt 0 ] \|\| exit 5` | n empty or not a number (`[` status 2) | `exit 5` | handled |
| 94 | `start=$(date +%s)` | | | handled |
| 96 | `$outlets` unquoted | set (maybe empty), digits only | | handled |
| 96 | `Rscript … > "$log" &` | redirect fails, so the subshell exits 1 | through 161 and 166: no result line, so 5 | handled |
| 96 | Rscript not on PATH | | `wait` gives **127**, passed through | **unhandled. Probed: exit 127** |
| 102-121 | `sample()`: `<(top …)`, `<(ps …)` | either fails (status always lost) | empty input, so awk prints `ERR`; three in a row give 4 | handled |
| 103 | `$pid` in `sample` | | set | handled |
| 128 | `kb=$(sample \|\| echo ERR)` | awk fails | `ERR` | handled |
| 129-139 | non-numeric or 0 `kb` | | retries, then `killed="memory…"`, so 4 | handled |
| 141 | `[ … ] && peak=$kb` | false test | not last in a function, so `set -e` does not fire | handled |
| 147-148 | `level=$(sysctl … \|\| echo 100)` | prints empty or non-numeric | `[` errors inside `if`, so the floor is silently skipped (fails open) | unhandled, negligible (the key exists on macOS) |
| 156 | `echo "$killed" >> "$log"` | write fails (disk full) | `set -e`, **1** for a cap kill; the EXIT trap still kills R | unhandled, low |
| 157-158 | `stop_run`; `case $killed in memory*` | | 4 or 3 | handled |
| **161-162** | `wait "$pid" \|\| r_rc=$?`, `rc=$r_rc` | R exits with anything other than 0/1 | **passed through raw** | **unhandled.** Probed: R exit 2 gives **2** (collides with "bad arguments"; `Rscript` exits 2 on an R fatal error, probed with a missing script); SIGKILL gives **137**, SIGSEGV **139**. Contract says 5. A macOS memory-pressure (jetsam) SIGKILL of R, the failure this script exists to manage, reports 137, not 3 or 5 |
| 166 | `[ "$rc" -ne 1 ] \|\| grep -q … \|\| rc=5` | log missing (grep 2) | 5 | handled, but only for 1 (see 161) |
| 168-169 | `$(grep -o … \|\| true)` | | `?` placeholders | handled |
| 170 | `summary="…$(awk …)…$(date …)…"` | awk or date fails | an assignment's status is its last substitution's, so `set -e` exits with it and skips runs.log | unhandled, negligible |
| 170 | `$name $wscode $group $rc $peak $start $lines $result` | unset | all set on every path that reaches 170 | handled |
| **171** | `echo "$summary" \| tee -a "$dir/runs.log"` | runs.log unwritable | `pipefail` + `set -e`: **1 replaces the run's code** | **unhandled. Probed: clean run (rc 0), exit 1** |
| **171** | same | stdout is a closed pipe | tee dies of SIGPIPE before writing the file: **141, and the runs.log line is lost** | **unhandled. Probed (`… \| true`): 141, no runs.log line** |
| 172 | `exit "$rc"` then the EXIT trap | | rc kept (probed: `trap "rm -rf …" EXIT; exit 5` gives 5) unless line 77 fails | handled |

## Findings

- **[bug] extras/mainflow_tree/ssnbler_check.sh:161-162 (with 166):** only R's status 1 is mapped. Every other
  non-zero R status reaches the caller raw. Measured with a stub:
  - R exit 2 gives **2**. That is a contract code, "bad arguments or a run already going". Real `Rscript` exits
    2 on an R fatal error (`Fatal error: cannot open file …`, probed).
  - SIGKILL gives **137** and SIGSEGV gives **139**. A missing Rscript gives **127**.

  The contract says 5 ("R failed"). The case that matters most: macOS's memory-pressure killer SIGKILLs R. That
  is the failure this wrapper exists for, and it reports 137, a code the README does not list, rather than 3 or
  5. Fix: after the wait,
  `case $r_rc in 0|1) ;; *) echo "R exited $r_rc" >> "$log"; r_rc=5 ;; esac`
  so the raw status survives in the log and the summary (or add an `r_exit=` field to the summary).
- **[bug] extras/mainflow_tree/ssnbler_check.sh:91:** `n=$(ogrinfo … | awk …)` under `set -e -o pipefail` exits
  with ogrinfo's status (1) before the `|| exit 5` guard on line 92 is reached. Probed: exit 1, no runs.log line.
  This is the same "export failed, reported as node errors" case that round 2 fixed for ogr2ogr, one line
  further down. Fix: `n=$(…) || { echo "could not count $name" >&2; exit 5; }`.
- **[fragile] extras/mainflow_tree/ssnbler_check.sh:171:** the summary `echo | tee -a runs.log` sits under
  `pipefail` + `set -e`, so a failure there replaces the computed `rc`. Probed:
  - runs.log unwritable: a clean run exits **1**, which reads as node errors.
  - stdout a closed pipe: exit **141**, and tee dies of SIGPIPE writing stdout before it writes the file, so the
    runs.log line is lost.

  Fix: write the file and stdout separately and do not let either decide the exit, e.g.
  `echo "$summary" >> "$dir/runs.log" || echo "could not append to runs.log" >&2; echo "$summary" || true`.
- **[fragile] extras/mainflow_tree/ssnbler_check.sh:77 (EXIT trap):** under `set -e`, a failing command inside
  the trap overrides an `exit N` in progress (probed: `set -e; trap 'false' EXIT; exit 3` exits 1). Every
  command in `stop_run` is guarded; `rm -rf "$lock"` is not. Low probability. `rm -rf "$lock" || true` closes it.
- **[fragile, low] extras/mainflow_tree/ssnbler_check.sh:41, 58, 156 (and 21, 86, 170, negligible):** unguarded
  setup or log writes exit via `set -e` with 1, the "node errors" code. 41 and 58 run before the trap; 156 runs
  on the cap-kill path, so a disk-full write there turns a 3 into a 1. These all need a write to fail. Listed
  for completeness, not because they are likely.

Not this mechanism (for the record): the TERM probe left the stub's own `sleep` child alive.
`stop_run` kills R and the tagged workers but not other descendants of R, while `sample()` counts
them. For real R the only descendants are the PSOCK workers, which carry the tag, so this is a stub artifact
unless SSNbler starts a `system()` child.
