# Code-check round 3: branch 42-pcic-crosswalk-keep-the-per-year-series (base d6e45c2, HEAD 5c62a92)

## Checklist read

- code-check-python.md: in full.
- code-check-infra.md: in full (38,115 bytes). Evidence blocks and `|` rows skipped.
- code-check.md: index in full. The prose of all 14 H3s under `## Mechanisms` (`|` rows and evidence skipped), read closely for "Written data outlives the fix", "A guard's scope, escape hatches, and remedies", "One fact derived twice", "A guard that fails toward pass" (provenance, the write path) and "Restore the bug and prove the guard fires". Index lines only for "Rules that stand alone", Security and Spreadsheets/PDF.
- code-check-shell.md, code-check-r.md, code-check-spatial.md: index in full (the same text CLAUDE.md carries). Their full sections were read in rounds 1 and 2 for every heading this diff touches (psql dollar-quote interpolation, EXIT traps, bash 3.2, xargs/ARG_MAX, Postgres row order, `grep -c`). Nothing in round 2's fixes uses a tool those sections did not already cover, so I did not re-read them.

Probes (I did not touch database `fwapg`, the run42 worktree or any `data/`):

- **Test suite.** I ran the full `pcic_test.sh` in a `git ls-files` copy (`scratchpad/rv3t.AkaIKe`, databases renamed `pcic_rv3_test`, `pcic_rv3_load`, `pcic_rv3_days`), 01:26:10 to 01:30:10 UTC. Result: 162 ok, `all pcic tests pass`. Round 2's four fixes added no checks, so the suite is the same 162.
- **Kept-file decision.** I took the job's own decision loop out of `pcic_crosswalk.sh` with `sed` and ran it in a scratch git repo (`scratchpad/rv3.BxnY9M`) against a real parquet. `pcic_days.py parquet` wrote that file stamped with commit A. Results:
  - **COMMIT=A:** kept.
  - **Commit B, changing only `sql/pcic_crosswalk06_subbasins.sql`:** kept.
  - **Commit C, changing `pcic_days.py`:** "built by other code ... rebuilding it".
- **`same_commit`.** I ran the extracted function four times:
  - **Clean tree:** passes.
  - **Dirty tree:** refuses.
  - **HEAD moved:** refuses.
  - **Edit made and reverted before the check:** passes.

## Mechanism

The guess is confirmed, with one refinement. The job decides two questions by a file's presence at a name, not by an identity the file carries:

- **"Is this step already done?"** The file at this name counts as current.
- **"Do these two artifacts agree?"** Whatever sits at both names at the moment counts as a matching pair.

#42 widened both sides. Each artifact now depends on more: the crosswalk, the code, the commit and the kept NetCDF. And the job writes more artifacts: kept NetCDF, per-year files and a catalogue. Each fix so far widened one proxy, on one axis. The eight findings split into two arms of this one root:

- **(a) Reuse keyed on fewer inputs than the write depends on.** A cache is reused because a file exists at a key that omits something it was built from:
  - R1-2: parquet reused on its path, without crosswalk or commit.
  - R1-3: `cat $DAILY/*.csv`, keyed by the directory, not by the current batch list.
  - R2-3: parquet reused without the code that built it.
  - R2-4: the fetch skipped because the climatology CSV was present, after the product set had grown to include the NetCDF.
- **(b) Coupled artifacts that must agree are written, checked or published at different moments, with no shared generation id.** A failure between the moments leaves a mixed state:
  - R1-1: the series guard was evaluated before the step that would satisfy it.
  - R1-4: code that fetches `pcic.series.csv.gz` merges before the file exists.
  - R2-1: two `.csv.gz` files written hours apart.
  - R2-2: the commit stamp captured at start, while the code is read per year.

  Arm (b) is arm (a) with time as the missing key component: the pair is matched by name and "latest" rather than by a generation both carry.

Where the job did attach identity, the checks hold: `crosswalk_md5` on `pcic.runs` and `pcic.series` rows, and `fwapg.crosswalk_md5` / `fwapg.commit` in the parquet metadata. What is left below is the inputs and moments that still have no identity attached.

## Enumeration (artifact | depends on | invalidated by | handled?)

| artifact | depends on | invalidated by | handled? |
|---|---|---|---|
| `data/{rivers,lakes}/*_NNNNNN.geojson` pages | PCIC's network at fetch time, `PAGE` | never (presence, `-s`) | Pre-existing, outside the diff. It freezes `pcic_outlets`, which every key below assumes is stable. |
| `$SERIES/batch_GGG_KKKK.txt` | `fwapg.pcic_outlets` order, `BATCH` | `rm` and regenerated every run (256-258) | Yes |
| `$SERIES` children `*a.txt`/`*b.txt`, `.split`, `.missing`, `missing.txt` | the parent list's composition at split time; model and scenario (dir); hydromosaic's domains | never (by hand, `rm $SERIES`) | Pre-existing (per run in #25, per model and scenario now). A stale `.split` would route a changed parent to old children. That is reachable only if the network pages are refetched. Not introduced. |
| `$NC/<batch>.nc` | model and scenario; the batch's outlet set; a complete transfer; hydromosaic's data at fetch time | an outlet-set mismatch (192) leads to a refetch; tmp file, `ncdump -h`, then `mv` | Composition and transfer: yes. Data version: no, by design ("one fetch"). But see the derived caches below. |
| `$DAILY/<batch>.csv` | `RUN` (model, scenario, `YEARS`); batch name; the NetCDF's content; `reduce_batch` code | never (presence, 193 and 213) | R1-3 fixed which files are read. The file is not tied to the NetCDF it was reduced from: finding 3. |
| `data/days/<MS>/pcic.subbasin_days.<MS>.<year>.parquet` | the NetCDF's content; the crosswalk (`dowsubid`, `anchor_subid`, `fwa_parent_subid`, `flag`, all in the md5); `days_build.sh`, `pcic_days.py`, `06_daily.sql`; `06_subbasins.sql` (`pcic_subbasins`, `fwa_depth`, which `06_daily` reads by name); the tree staying at the stamped commit for the whole build | md5 mismatch, or `git diff` of the three files, leads to a rebuild (430-440) | Crosswalk: yes. The three files: yes (probe C). `06_subbasins.sql`: no (probe B): finding 4. Tree at the stamp during the build: no: finding 1. NetCDF content: no: finding 3. |
| `.parquet.tmp`, `${tmp}_day.*`, `$out.tmp`, `*.csv.gz.tmp` | transient | overwritten; outside every glob | Yes |
| staging `fwapg.pcic_*` (with `pcic_subbasins_months`, `pcic_days_means`, `pcic_series_files`, `pcic_outlet_year_<y>`) | the current run | rebuilt each run, or dropped on exit | Yes. `RAN_ALL` gates the months check on kept years. |
| `pcic.runs` (build DB) | crosswalk, weights, the run's tables | replaced per key, with the export's refusals | Yes (pre-existing) |
| `pcic.series` (build DB) | the files in `data/days/<MS>/`; the crosswalk | replaced per model and scenario by `pcic_export_days.sql`. With `DAYS=1`, old-crosswalk rows are deleted in `pcic_export.sql`, otherwise refused | Crosswalk axis: yes. A kept file removed at 434/438 for a code change keeps its row until `export_days` runs: finding 2. |
| `extras/pcic_crosswalk/pcic.*.csv.gz` (shared) | DB state at export | rewritten each run; `pcic.series` at 401 and 474 | `runs`/`series` crosswalk pairing: yes (R2-1). Series file against the files after a failed run on an unchanged crosswalk: no (finding 2). |
| `pcic.<table>.<run>.csv.gz` | that run's rows | rewritten when that run reruns | Yes (pre-existing; `load/pcic_run.sql` checks each file against `pcic.runs`) |
| S3 `fwapg/extras/*` | the local files at upload time | a human upload, catalogue first, files second (`extras/README.md`) | No order or consistency gate: finding 2. |
| consumer `pcic.series` (`load/pcic.sql`) | the published catalogue and crosswalk | replaced per published model and scenario. A model and scenario absent from the published file is kept, and refused if on another crosswalk | By design, matching `pcic.runs`. |
| `pcic.series.commit` / `fwapg.commit` | a commit a reader can resolve | nothing checks it was pushed | Note only (accepted as deliberate). |
| `fwapg.pcic_qa_build` | crosswalk and run | dropped at start | Yes (pre-existing) |

## Findings

- **[fragile] extras/pcic_crosswalk/pcic_crosswalk.sh:41-52, :450 and :468, with days_build.sh:35, :38 and :44.** The stamp and the code it names are still taken at different moments.
  - **How the stamp and the code diverge.** `COMMIT` is captured once, at the start guard. Every year's `days_build.sh` then re-reads `pcic_days.py`, `days_build.sh` and `sql/pcic_crosswalk06_daily.sql` from the working tree and writes `fwapg.commit = $COMMIT` into the file. `same_commit` checks only the tree's state at catalogue time, and its failure path removes nothing.
  - **Sequence one: an edit discarded after the refusal.** An uncommitted edit lands mid-run. The years built after it carry the stamp `$COMMIT`. `same_commit` refuses (dirty), or `qa_days.sql` fails first. The edit is then discarded (`git checkout`, `git stash`) and the job rerun at `$COMMIT`. Every one of those files is kept: its md5 matches and `git diff COMMIT COMMIT` is empty (probe case 1). They are catalogued as built by `$COMMIT`.
  - **Sequence two: a tree moved and moved back.** A checkout of another commit and back during the run passes `same_commit` (probe).
  - **Where it is silent.** Mostly it is caught, because `qa_days.sql`'s mean check fails when a kept in-`YEARS` year's values moved. It is silent when the affected years lie outside `YEARS`: 1950 by default, and 2011-2012 at the end of the queue with `YEARS=1981/2010`, the last years built.
  - **Fix.** Freeze the three files at the start guard (copy them, with `sql/`, into a `mktemp -d`) and run `days_build.sh` from the copy. `days_build.sh` resolves `pcic_days.py` and `06_daily.sql` through `$D=$(dirname "$0")`, so a copy runs as is. The stamp is then true by construction. Second best: on `same_commit` failure, `rm` the files of `$TODO` before exiting.

- **[fragile] extras/pcic_crosswalk/pcic_crosswalk.sh:401 with :434/:438, and extras/README.md:27-32.** R2-1 closed one axis of the catalogue/files window, the crosswalk. The pair can still be published mixed in two ways:
  - **A failed `DAYS=1` run on an unchanged crosswalk, after a code change.** `pcic_export.sql` deletes nothing here, because the md5 matches. Line 401 writes `pcic.series.csv.gz` with the old rows. Lines 434/438 then `rm` the kept files, and `days_build.sh` rewrites some of them. If the days step fails, `data/days/<MS>/` holds new files, or none, under the old catalogue. The README's parquet loop uploads every file there, so S3 then holds files whose `bytes` and sums do not match the published `pcic.series` rows. The build DB's rows likewise describe files that no longer exist.
  - **The README's upload order.** It sends `pcic.*.csv.gz` first and the parquet files second. An interrupted parquet loop (about 9 GB, a production write that auto mode may refuse midway) publishes a catalogue for files that are not up yet.
  - **Consequence.** A reader that checks `bytes` and the sums refuses, so this is loud for wet. But the published state is wrong until someone re-uploads.
  - **Fix.** Upload the parquet files first and `pcic.series.csv.gz` last, and only after the run printed `PCIC crosswalk complete`. Have the upload step compare `pcic_days.py fingerprint data/days/<MS>/*.parquet` with the model and scenario's rows in `pcic.series.csv.gz` before sending either. Or, when the decision loop removes any kept file, delete that model and scenario's `pcic.series` rows and re-export the file there. That last one has the same premise R2-1 had: an upload after a failed run.

- **[fragile] extras/pcic_crosswalk/pcic_crosswalk.sh:128-129 (the remedy), with :193, :196 and :213 and the parquet decision at :430-440.** The comment "remove $NC and $SERIES to fetch the model and scenario again" refreshes no product. The usual reason to refetch is that hydromosaic's data changed, and the run then succeeds silently on the old data.
  - **`DAYS=0`.** Nothing is fetched, because line 196 returns while `$DAILY/<batch>.csv` exists.
  - **`DAYS=1` or `FETCH_ONLY=1`.** The NetCDF is fetched again, but every run's `$DAILY` CSV is kept (`[ -e "$out" ] ||` at 193 and 213). Every parquet file is kept too: the crosswalk md5 and the commit are unchanged.
  - **Why nothing catches it.** The climatology and the per-year files are then both from the old fetch. They agree, so `qa_days.sql` passes and the old data is catalogued.
  - **Cause.** Neither derived cache carries the identity of the NetCDF it came from.
  - **Fix.** Name `data/daily/<model>_<scenario>_*/` and `data/days/<MS>/` in the remedy. Better, re-reduce when `[ "$nc" -nt "$out" ]` at 193, reduce unconditionally after a fresh download at 213, and rebuild a parquet file older than any of `$NCS`.

- **[fragile, low] extras/pcic_crosswalk/pcic_crosswalk.sh:436.** The list of code a file depends on omits `sql/pcic_crosswalk06_subbasins.sql`. That file builds `fwapg.pcic_subbasins` and its `fwa_depth`, which `06_daily.sql` reads by name to order the accumulation. A commit changing only it keeps every file (probe B). It is not silent: the climatology is rebuilt with the new code, so `qa_days.sql`'s mean check fails on the kept in-`YEARS` years. But the failure reads "QA of the per-year days failed", with nothing pointing at stale files. Fix: add the file to the list (over-key).

## Round-2 fixes: checked

- **Fix 1 (`export_table pcic.series` at 401).** The database is consistent at that point (old-crosswalk rows deleted; nothing new written), and line 474 rewrites the file after `pcic_export_days.sql`. The remaining window is on the code axis (finding 2), not the crosswalk axis.
- **Fix 2 (`same_commit`).** It refuses a dirty tree and a moved HEAD, and passes a clean one (probe). It sees only the end state (finding 1). Tracked files only is accepted.
- **Fix 3 (code diff on resume).**
  - Pathspecs are relative to `extras/pcic_crosswalk`, as written. A change to `pcic_days.py` rebuilds; a change outside the list keeps (probes C and B).
  - An empty or unknown commit fails `git cat-file -e` and rebuilds. Any `git diff` error also rebuilds, so the check fails safe.
  - A docstring edit to `pcic_days.py` rebuilds all 63 years. That over-keys, which is the safe direction.
- **Fix 4 (`FETCH_ONLY`).** `FETCH_ONLY` is exported to the `xargs` children, the early return at 196 is skipped for it, and the NetCDF check at 264 now runs for it. A `.missing` leaf needs no NetCDF.

## Not findings (noted)

- **`extras/pcic_crosswalk/README.md:148-149` is stale since rounds 1 and 2.** It still says "a year whose file exists is skipped, so a rerun resumes". A kept file is now rebuilt when it was routed on another crosswalk or built by other code, as `pcic_crosswalk.sh:414-416` says. Fold this into Phase 6.
- **None of round 2's four fixes is pinned by a check in `pcic_test.sh`.** Their behaviour is shown by the probes above. Deleting any one of them leaves the suite green.
- **`meta=$(uv run ... meta "$f")` at 431 runs under `set -e`.** A damaged file therefore stops the job, rather than "falling through to a rebuild" as round 2 wrote. Both commits' writer uses a tmp file and `os.replace`, so a killed write never leaves a damaged `.parquet`. Loud either way.
