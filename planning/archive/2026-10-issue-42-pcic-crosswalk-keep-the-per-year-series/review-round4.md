# Code-check round 4: branch 42-pcic-crosswalk-keep-the-per-year-series (base d6e45c2, HEAD 2ed228a)

## Checklist read

- code-check-python.md: in full. Checked the 3.11 floor: `pcic_days.py` parses under `uv run --python 3.11` (ok).
- code-check-infra.md: in full. Evidence blocks and `|` rows were skipped. The Docker / Postgres section was read closely; the cloud-init, tofu, DO and Tailscale sections do not apply.
- code-check.md: index in full, and the prose of all 14 H3s under `## Mechanisms`. These were read closely:
  - "A guard that fails toward pass": Where the guard sits; a comment stating a property; The write path; Provenance.
  - "A guard's scope, escape hatches, and remedies".
  - "Written data outlives the fix": diff the ledger against the artifacts it claims.
  - "One fact derived twice".
  - "A proxy is not the property": mtime as a stand-in for the NetCDF's identity.
- code-check-shell.md: index in full. Full sections read for the tools round 3's fixes use: "`mktemp` template", "A second `trap … EXIT` replaces the first" (with its bash 3.2 paragraph), "Put cleanup on the EXIT trap", "`cmd dir/*` dies on ARG_MAX", and "On this Mac `stat` and `date` are GNU".
- code-check-r.md, code-check-spatial.md: index only. Nothing in round 3's fixes touches R or spatial tooling.

Probes. I did not touch database `fwapg`, the run42 worktree or any `data/`.

- **Test suite.** I ran `pcic_test.sh` in a `git ls-files` copy (`scratchpad/rv4.*`, databases `pcic_rv4_test`, `pcic_rv4_load` and `pcic_rv4_days`). Result: 162 ok, `all pcic tests pass` (log `scratchpad/rv4_test.log`, last written 01:49:20 UTC).
  - The trap's final `DROP DATABASE` then waited on `IPC/CheckpointStart` for more than 9 minutes. The checkpointer was in `DataFileWrite`, flushing the running build's dirty buffers.
  - The suite never runs `pcic_crosswalk.sh` as a whole, so `$CODE` is untested by it.
- **Sub-second `-nt` and `find -newer`.** `fetch_batch` runs under `xargs bash -c`, which is the PATH bash: Homebrew bash 5, with sub-second times. The script itself runs under `/bin/bash` 3.2, with whole seconds.
  - A NetCDF and a CSV in the same second, CSV later: both bashes keep the CSV. That is right.
  - A NetCDF later in the same second: bash 5 reduces again; bash 3.2 keeps the CSV. Unreachable in sequence: the fetch, then `reduce_batch`, take seconds.
  - `find -newer` is sub-second.
  - The direction is right on a first run, on a FETCH_ONLY-warmed cache, and on a fresh fetch. On a fresh fetch, `mv` keeps the end-of-transfer mtime and `reduce_batch` now runs unconditionally after it.
- **bash 3.2 with an `EXIT` trap** (`/bin/bash` 3.2.57, `set -euxo pipefail`, `trap 'rm -rf "$C"' EXIT`):

  | error | exit with the trap | exit without |
  |---|---|---|
  | unbound `$UNDEF_X` | **0** | 1 |
  | `: "${ZZ:?}"` | **0** | 1 |
  | `false` | 1 | 1 |
  | `x=$(false)` | 1 | 1 |
  | `exit 3` | 3 | 3 |
  | missing command | 127 | 127 |
- **In-place edit of a running bash script.** `/bin/bash x.sh` was sleeping when the file was rewritten in place (same inode). It printed the *edited* line.
  - The Edit tool here writes a new inode (186692035 → 186692039, probed), and so does `git checkout`. Both are safe for a running bash.
  - An editor or `>` that writes in place is not.
- **uv and `$CODE`.** uv 0.12.5 keys a script's environment on its path:
  - Each probe at a fresh path created a new `~/.cache/uv/environments-v2/pcic-days-<hash>`, 179 MB by `du`.
  - Four concurrent first uses at one fresh path all succeeded.

## Enumeration verdict: missing rows and two wrong verdicts

**Missing rows, all handled.** None of these is a hole; they belong in the table so that "every artifact" is true:

| artifact | depends on | kept only while | status |
|---|---|---|---|
| `data/rivers.geojson`, `data/lakes.geojson` (merged pages) | the pages | rewritten every run | handled |
| `data/qa_drainage.csv`, `data/qa_following.csv` | the run | rewritten every run | handled |
| `fwapg.pcic_qa_outlets`, `_candidates`, `_flow`, `_drainage`, `_following`, read by `review_build.sh` | the run, the crosswalk | gated by `fwapg.pcic_qa_build`, which is dropped at start and written last | pre-existing, handled. Round 3's table had this row; findings.md dropped it. |
| `.nc.tmp`, `.csv.tmp`, `${batch}_day.*`, `.parquet.tmp`, `.csv.gz.tmp` | transient | outside every glob and loop that reads | handled. Round 3 had this row. |
| uv script environment for `$CODE/pcic_days.py` | `pcic_days.py`'s dependency ranges, resolved when the environment is created | new per run, because uv keys it on the script's path and `$CODE` is new each run | handled for correctness: each file's fingerprint is its own, and values do not depend on pyarrow or numpy version. Leaves one environment per run in the uv cache (note below). |

**Wrong verdicts:**

1. **"code run | the tree at COMMIT | copied once at start | handled (R3-1)".** Only `sql/`, `days_build.sh` and `pcic_days.py` are frozen. Finding 3 has the detail. Two other files are still read from the tree hours in:
   - `pcic_crosswalk.sh` itself. bash reads it incrementally (probed).
   - `../../load/pcic_schema.sql`, read at line 389. The clean-tree guard covers `../../load`.
2. **"pcic.series (build) … handled", "pcic.\*.csv.gz … handled" and "fresh-bc objects | uploaded after `complete`, parquet first | procedural (R3-2)".**
   - The decision loop removes kept files on the code and NetCDF axes (lines 441-445). It leaves their `pcic.series` rows in place until `pcic_export_days.sql` runs.
   - `PCIC crosswalk complete` is printed by *every* successful run, including `DAYS=0` and other models. Every run also rewrites `pcic.series.csv.gz` from the database (line 405).
   - So "after complete" does not imply that the catalogue and `data/days/*/` agree. Finding 1.

The rest of the table checks out against the code:
- NetCDF: outlets, then `mv` after `ncdump -h`.
- CSV: `! nc -nt out`, with only current leaves read.
- Parquet: md5, the four files' `git diff`, `find -newer`.
- `pcic.runs`, and the consumer refusals.

## Findings

- **[fragile] extras/pcic_crosswalk/pcic_crosswalk.sh:436-446, :405, :501, with extras/README.md:25-31.** The catalogue and the files can still be published mixed. Round 3's fix (R3-2) gates the upload on `PCIC crosswalk complete`, but that line is not specific to the model whose files changed. Sequence, by reading:
  1. A `DAYS=1` run of model B on an unchanged crosswalk, after a change to `pcic_days.py`, `days_build.sh` or the `06` SQL, or after a refetch. `pcic_export.sql` deletes nothing (md5 equal). Lines 441/445 `rm` B's kept files and the rebuild starts. The run fails partway (a crash, or `qa_days.sql`). The database's `pcic.series` still holds B's old 63 rows. `data/days/B/` holds some new files and is missing the rest.
  2. Any later run that succeeds prints `complete`:
     - a `DAYS=0` run of another period, through line 405 and `pcic_export.sql` (days=0 refuses only a crosswalk mismatch);
     - or model A's `DAYS=1` run.

     It rewrites `pcic.series.csv.gz` with B's stale rows.
  3. The README's procedure then uploads every `data/days/*/` file, B's mixed directory included, and the stale catalogue after it.

  S3 now holds B files whose `bytes`, sums or `commit` do not match the published rows. On the refetch axis the values differ too. A reader that checks fingerprints refuses, so this is loud for wet. `load.sh` never looks at the files, so the consumer database accepts the catalogue. This is "Written data outlives the fix" / "diff the ledger against the artifacts it claims".

  Fix, either or both:
  - **(a)** Gate the upload mechanically. Before uploading `data/days/<MS>/`, compare `pcic_days.py fingerprint data/days/<MS>/*.parquet` with the `<model>,<scenario>` rows of `pcic.series.csv.gz` (or `pcic.series`), and skip or refuse a model whose files and rows differ.
  - **(b)** In the decision loop, before the first `rm` of a kept file, delete that model and scenario's `pcic.series` rows and re-export `pcic.series.csv.gz`, so the catalogue never lists a file the loop removed. (b) alone still lets the parquet loop upload B's partial directory, so the README loop should also be limited to the model whose `DAYS=1` run printed `complete`.

- **[fragile] extras/pcic_crosswalk/pcic_crosswalk.sh:51.** The new `trap 'rm -rf "$CODE"' EXIT` changes the script's exit status. Under `#!/bin/bash` (macOS 3.2.57) with `set -u`, an armed EXIT trap turns an expansion error into **exit 0**: an unbound variable, or a `${X:?}`. Probed: 0 with the trap, 1 without (the code-check-shell.md rule "A second `trap … EXIT`", its bash 3.2 paragraph).
  - Nothing after line 51 is unbound today: `COMMIT` is set whenever step 6 can run, and `DATABASE_URL` fails at line 18, before the trap. So this is latent.
  - But it is a 500-line script under active edit. A typo'd variable in a later change would stop the run midway and report success to anything gating on the exit status: a background-task notification, a `&&` chain, a waiter. Only the absence of the `complete` line would show it.
  - Fix, the convention's pattern:

    ```bash
    ok=0
    trap 'rc=$?; rm -rf "$CODE"; [ "$ok" = 1 ] || exit $(( rc ? rc : 1 ))' EXIT
    ```

    Then set `ok=1` before the final `echo` and before the FETCH_ONLY `exit 0`.
  - `days_build.sh:30` (new in this branch) has the same shape. There an exit 0 makes `xargs` count a year as built. `pcic_export_days.sql`'s "years % of the series have no file" catches that later, loudly.

- **[fragile, low] extras/pcic_crosswalk/pcic_crosswalk.sh:47-52 and :389, with extras/pcic_crosswalk/README.md:151-152.** Both the comment and the README claim that "an edit or checkout during it must not reach it". The copy does not include two files the run reads late:
  - **`pcic_crosswalk.sh` itself.** bash reads its script as it runs. An in-place write to it mid-run (an editor that keeps the inode, `cat >`, `printf >`) changes what the running job executes (probed). `git checkout` and the Edit tool write a new inode and are safe. The `if [ "$DAYS" = 1 ]` block is parsed whole only when it is reached, after hours of fetch and placement. So the decision loop, the arguments to `days_build.sh` and the catalogue export can all come from the edited file while the files are stamped `$COMMIT`.
  - **`../../load/pcic_schema.sql`.** psql opens it by path at line 389, hours in, so a checkout or edit does reach it. The clean-tree guard includes `../../load` for this reason. Its statements are `CREATE ... IF NOT EXISTS`, so on a database that already has the tables a change has no effect, and on a fresh one `pcic_export.sql` fails loudly on a mismatch.

  Fix, choose one:
  - Copy `../../load/pcic_schema.sql` into `$CODE` too.
  - Wrap the script body in `main() { ...; }; main "$@"`, or `{ ...; exit; }`, so bash parses it whole before running.
  - Narrow the comment and README to the files actually copied. The run42 worktree already sidesteps this in practice.

## Round-3 fixes: checked

- **R3-1 (`$CODE`).**
  - `cp -R` keeps the execute bit, and `days_build.sh` resolves `$D=$(dirname "$0")` to `$CODE`. `sql/pcic_crosswalk06_subbasins.sql`'s `\ir pcic_crosswalk06_daily.sql` resolves relative to the file, so to `$CODE/sql`. No other SQL file uses `\ir`, `\i`, or a relative `\copy` or path.
  - The `data/...` paths, `../../load` and `../blue_line_paths` stay relative to the cwd, which is unchanged.
  - The `git diff` pathspecs are evaluated in the cwd against git objects, not against `$CODE`, which is correct.
  - `mktemp` uses six X's and is fatal under `set -e`; the trap is the script's only one.
  - `xargs -I {}`: `$CODE` holds no `{}`, so BSD xargs' 255-byte replacement limit applies only to the year and the parquet path, as before.
  - `uv run --script "$CODE"/pcic_days.py` works, including four concurrent first uses. It builds a new environment per run (note below).
  - Gaps: finding 2 (trap exit status) and finding 3 (scope).
- **R3-2 (upload order).** Parquet first is the right order for files that are new. For a *replaced* file, the live catalogue describes the old bytes between the two loops, and either order has that window without versioned names. Loud for a checking reader; noted, not a finding. The remaining hole is finding 1.
- **R3-3 (`-nt`, unconditional reduce after a fresh download, `find -newer`).** Correct direction in every case probed above. `.nc.tmp` is excluded by `-name '*.nc'`. A stale non-leaf NetCDF in `$NC` can only over-key. Under `pipefail`, `find | head -1` inside `[ -n "$(...)" ]` cannot trip `set -e`.
- **R3-4 (`06_subbasins.sql` in the list).** Present at line 440. `06_daily.sql` reads `fwapg.pcic_outlets (subid, dowsubid)`, `pcic_fwa_crosswalk` and `pcic_subbasins`. `dowsubid` comes from PCIC's pages and is also in the crosswalk md5, so `00_outlets.sql` needs no entry in the list.

## Not findings (noted)

- **mtime is a proxy for the NetCDF's identity.**
  - In the over-key direction, any rewrite of `data/nc/` that sets mtimes to now re-reduces every CSV and rebuilds all 63 years, about 5 h. That includes a `cp -R` without `-p` and a `touch`. Costly, never wrong.
  - In the under-key direction, a NetCDF replaced by different content carrying an *older* mtime keeps both caches. Examples: `cp -p`, `rsync -t`, or an `aws s3` restore, which sets LastModified. Out of scope under "one fetch, by design".
- **uv environments accumulate.** Each run leaves `~/.cache/uv/environments-v2/pcic-days-<hash of $CODE>` (179 MB by `du`; clonefile on APFS may share most of it). Each run also resolves `netCDF4>=1.6`, `numpy>=1.26`, `pyarrow>=15` afresh, so kept and rebuilt files in one catalogue may come from different library versions. Values are unaffected. `uv cache prune` reclaims the space.
- **`ncdump -h` checks the header only.** A transfer truncated with a clean HTTP 200 would be kept and then fail `reduce_batch` loudly on every rerun until it is removed by hand. Not silent.
- **Test cleanup can be slow while a build runs.** `pcic_test.sh`'s `DROP DATABASE` requests an immediate checkpoint, which waits on the build's dirty buffers.
