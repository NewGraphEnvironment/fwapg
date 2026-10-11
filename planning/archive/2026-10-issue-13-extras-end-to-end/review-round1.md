# Review round 1: 97334ce...HEAD, extras/ and research/

Reviewed 2026-10-10. Read in full: `ssnbler_check.sh`, `ssnbler_check.R`, `qa_topology.sql`,
`pcic_crosswalk02_candidates.sql`, the three READMEs' changed sections, `research/fwa_mainflow_tree.md`,
`planning/active/findings.md` and `review-watchdog.md`. No job scripts were run and nothing was written to the
database. Probes: the `sample()` function, extracted into a scratch script on `/bin/bash` 3.2.57, against a live
`sleep` (returned a KB figure) and after it exited (returned `ERR`). The validation regexes were also run on 3.2
(`100.`, `100x5`, `0`, `10000` rejected). SSNbler 1.1.2 source was read (`get_pdist_nodes`, `pdist_node_coords`,
`lines_to_lsn`).

## Findings

- **[severity: fragile, doc]** `extras/mainflow_tree/ssnbler_check.sh:42`: the comment says "two large networks
  in memory at once crashed the machine in fwapg#2". The record says three: `planning/archive/2026-10-issue-2-mainflow-tree/README.md:11`
  ("three parallel SSNbler runs crashed the machine three times"), the README in this diff ("three at once
  crashed a 64 GB machine") and the research file ("three at once caused kernel panics"). Fix: "three ... at
  once". This is a wrong number in a committed file, and it is the only claim in the diff that contradicts its
  source.

Nothing else found that could cause a failure or data loss. What was checked:

### ssnbler_check.sh
- Worker tag. SSNbler's `get_pdist_nodes`/`get_pdist_rid` call bare `makeCluster(ncores)`, which uses PSOCK and
  picks up `setDefaultClusterOptions(outfile=)`. The tag `OUT=$(pwd -P)/data/ssnbler/lsn_<name>.workers.log`
  matches R's `file.path(getwd(), args[2])`, because both are physical paths after the `cd`. It is not a prefix
  of another name's tag (`lsn_klum.workers.log` does not occur inside `lsn_klum2.workers.log`). Neither awk's
  nor ps's own command line carries the value, because it reaches awk through `ENVIRON`. macOS `ps` does not
  truncate `command` when its output is a pipe. `WORKER_TAG` is exported before the first `workers()` or
  `sample()` call and is never empty, so `index($0, "")` cannot match every process.
- `sample()`: the `FNR == NR` trap for an empty first file still ends in `ERR`, because `p` stays empty. The
  `top` unit parsing matches this machine's output (`K`/`M`/`G`). The ancestor walk compares strings and
  strnums correctly in bwk awk. `ERR`, non-numeric values and `0` all count as failures, and three in a row give
  exit 4.
- `stop_run`/`cleanup`: `workers()` is re-queried at each kill, so stale pids are not killed (the old F4). The
  loop condition is right: it keeps waiting while R or any tagged worker lives, then sends KILL after 10 s.
  The EXIT trap is set only after the lock is taken, so the "already running" exit leaves the other run's lock
  alone. HUP, INT and TERM go through `exit`, which runs the EXIT trap.
- Under `set -e`, every test that can be false sits in an `&&`, `||` or `if` context. `wait "$pid" || r_rc=$?` is
  safe. `$outlets` unquoted is intended.
- Lock takeover: two runs started at the same instant against a stale lock could both take it over. This is
  negligible in practice and not reported as a finding.

### ssnbler_check.R
- `parallel:::setDefaultClusterOptions` is also exported (`::` would do), and `:::` works. It is harmless on the
  serial path. The worker log sits beside the lsn directory, not inside it, so `overwrite = TRUE` cannot remove
  it while workers hold it open.

### qa_topology.sql
- Same predicate as before, as argued in `review-watchdog.md` Part 1. The tangency guard in findings (closest
  mouth 1.26 m from the threshold) makes the identical 504-row diff conclusive. `coalesce(..., false)` behaves
  the same when no piece intersects.

### pcic_crosswalk02_candidates.sql
- `s.downstream_route_measure` in both new `ORDER BY`s is qualified, so it resolves to the segment's input
  column and not to the computed output alias of the same name. That is what the tie rule needs: the computed
  measure is equal for both tied segments. Each ordering is now total (`linear_feature_id` is unique).
- In `side_moves`, the measure comparison is within one blue line (`s.blue_line_key = c.watershed_key`), so
  "upstream" has meaning there. The later dedup `DELETE` breaks ties by `(distance, linear_feature_id, ctid)`.
  For the same probe and blue line, both lookups now choose the same segment under the same rule, so the dedup
  cannot undo the upstream choice. The exception is a KNN-100 window edge case that the accepted tradeoff
  already covers.

### Docs vs code and findings
- The mainflow README timings (20 min = 16 + 3 + 1.5), the serial and parallel memory figures (28 GB/21.7k,
  52-54 GB/29-30k, 3.5/7.5/16/20 GB), "27 of 29 groups", the Nechako's 8 outlets, the Skeena's 6 errors, and
  "MSKE 4 vs 2" all match findings.md. The quadratic claim fits the numbers: 28 GB × (24.7/21.7)² ≈ 36 GB,
  and MSKE measured 37 GB.
- The research mechanism (chunk-local duplicate test, chunk-local row numbers applied with no offset, chunks of
  at most 500 below 280,000 to-nodes) matches the SSNbler 1.1.2 source. "Must run in parallel at 46,340 lines"
  matches `lines_to_lsn`'s `max.edges` check on `n_edges = nrow(in_edges)`.
- The PCIC README's "about 1%" fits 449 / 48,716 = 0.92%. That is a lower bound on ties, but close enough.
- No host names, tailnet, private-repo links or credentials beyond the accepted local default appear in the
  diff. `data/` is gitignored, so `runs.log`, `.lock` and `*.workers.log` cannot be committed.

### Notes (not findings)
- `extras/pcic_crosswalk/README.md:164` gives "2,184 of 36,380 sub-basins, 1,815 of 22,184 m³/s" for "the
  2026-10 build". findings.md says this was not re-derived after the tie rule moved 74 placements (14 with a
  local-code change). It may be stale by a few units. It is unverified, not shown to be wrong.
- The upstream-segment rule leaves Toba River 206063646 (75-122 m) with no flow, because the terminal outlet
  now takes the segment above. findings.md records this as a consequence of the user's decision. The PCIC
  README does not mention it.
