# Code-check round 3: branch `25-pcic-crosswalk-run-parameters` (a62c193 vs newgraph)

Reviewer: read-only. I did not connect to database `fwapg`, did not create a scratch database, and
edited no repo file except this one. I ran one shell simulation in a temp dir under /bin/bash 3.2: the
missing.txt bypass in finding 1. Every other verdict comes from reading the code.

## Mechanism

**One fact is held in several copies, each with its own writer, and each guard reads one copy as if
it were the fact.** Three facts are copied this way:

- **Which runs exist:**
  - `pcic.runs`;
  - the distinct `(model, scenario, period)` in the three per-run tables;
  - the `pcic.<table>.<run>.csv.gz` files, locally and on S3;
  - load.sh's hard-coded list;
  - `data/daily/<run>/`;
  - the run columns of `fwapg.pcic_qa_build` and `fwapg.pcic_qa_gauges`.
- **What a run's rows were built on:**
  - the fingerprints in `pcic.runs`;
  - the shared `pcic.fwa_crosswalk`, `pcic.segment_weights` and `pcic.day_bins`;
  - the staging `fwapg.pcic_*` tables;
  - the crosswalk md5 in `fwapg.pcic_qa_build`.
- **Which outlets have no series:**
  - `data/series/<run>/missing.txt`;
  - the empty CSVs in `data/daily/<run>/`, which become absence from `fwapg.pcic_outlet_daily`.

Each earlier finding is a guard that read one copy while a writer changed another:

| Round | The guard read | A writer changed |
|---|---|---|
| R1 | the crosswalk md5 | the weights |
| R1 | `pcic.runs` | the rows load.sh does not reload |
| R2 | `pcic.runs` | rows whose `pcic.runs` row was deleted |
| R2 | the stamp | `pcic_qa_gauges`, which had no run |

The fix each time was to compare one more pair of copies. Copies that nothing compares remain, below.

## Enumeration (place → covered by / not covered)

### Run identity

| Place | Verdict |
|---|---|
| `MODEL`/`SCENARIO`/`YEARS` → `PERIOD`, `RUN` (pcic_crosswalk.sh:19-33) | Covered: validated at :24-30. |
| The same derivation in qa_gauges.sh:22-27 and qa_gauge.sh:13-21 (a second and third copy) | Covered while the copies agree. Measured: they agree today. A drift in `RUN` fails closed at qa_gauges.sh:30 (no cache dir). A drift in `PERIOD` would be caught by review_build.sh:40-44. |
| The export's `run` temp table (pcic_export.sql:16-23), `RUNSQL` (pcic_crosswalk.sh:291) and the stamp (:306-309) | Covered: all three come from the same shell variables. |
| Per-run rows vs `pcic.runs`, at export | Covered: the orphan check (pcic_export.sql:39-50) and the "other" check (:30-38). |
| Per-run rows vs `pcic.runs`, at load/pcic.sql | Covered: the orphan check (:53-64). Runs in `runs_in` are cleaned by the stale-row deletes (:68-91), which delete when no local `pcic.runs` row matches. |
| Per-run rows vs `pcic.runs`, at pcic_run.sql | Covered: the file's run must be in `pcic.runs` (:42-48). |
| Export file name vs file content | Covered: pcic_run.sql takes the run from the content and checks it against `pcic.runs`. |
| load.sh's hard-coded list (load.sh:190) vs the published `pcic.runs` | **Not covered.** Nothing compares them. A listed run absent from `pcic.runs` fails every load. A published run not in the list is listed in `pcic.runs` with no rows. Finding 3. |
| `data/daily/<run>` cache vs the run's `YEARS` | Covered: `RUN` includes `PERIOD`, and :192-193 checks the day counts. R2 accepted the pre-fix-cache residual. |
| `pcic_qa_gauges` run vs `pcic_qa_build` run | Covered: review_build.sh:40-44 (R2 fix). Correct for one stamp row; a table with no gauges fails closed. |
| `pcic_qa_gauges` run vs the run's rows in `pcic.discharge_monthly` | **Not covered.** qa_gauges.sh never checks that the run is there. Finding 2. |
| `data/qa_drainage.csv`, `qa_following.csv`, `qa_gauges.csv` (no run in the name) | Not covered. No finding: nothing reads them as a set (grep). |

### What a run's rows were built on

| Place | Verdict |
|---|---|
| Export: the new crosswalk and weights vs other runs' fingerprints | Covered: pcic_export.sql:30-38. |
| load/pcic.sql: incoming runs vs the incoming crosswalk and weights | Covered: :37-42. |
| load/pcic.sql: local unpublished runs vs incoming | Covered: :46-52. |
| load/pcic.sql: stale local rows of published runs | Covered by crosswalk md5 plus the table's own fingerprint (:68-91). The weights are not in it. No finding: weights that differ change `monthly_rows` or `monthly_q_sum` in practice, and daily rows do not depend on weights. |
| pcic_run.sql: run vs `pcic.fwa_crosswalk` | Covered: :53-55. |
| pcic_run.sql: run vs `pcic.segment_weights` | Not compared directly. Covered by the invariant that every `pcic.runs` row matches the shared tables, which both writers of `pcic.runs` enforce (the export at :30-38, load/pcic.sql at :37-52). |
| `pcic.day_bins`: written by both writers, no fingerprint, only `count = 366` checked (load/pcic.sql:43) | Covered only because the table is a constant of 01_days.sql:17-34. A later change to the week formula at :32 would leave older runs' weekly rows under new weeks, and nothing would compare them. Holds today; no finding. |
| The fingerprint formula, written five times (pcic_export.sql:21, load/pcic.sql:28, pcic_run.sql:53, pcic_crosswalk.sh:307, review_build.sh:46) | Covered: all five are identical. The weights formula (export :22-23, load :29-30) and the per-table formulas (export :94/98/102, pcic_run.sql:38-40) also agree. |
| `pcic_qa_build` stamp vs what the review reads | **Partly covered.** The stamp holds the crosswalk md5 only. The review reads `pcic_qa_gauges`, which reads `pcic.discharge_monthly`, which depends on the weights too. Finding 2. |
| Staging `fwapg.pcic_day_bins`, owned by the job alone | Covered: R1 fix. qa_gauges.sh:71-79 counts the days inline. |
| `pcic_qa_*` kept tables vs a job in progress | Covered: the stamp is dropped at :44 and re-created last (:306). |

### Outlets with no series

| Place | Verdict |
|---|---|
| The ≤100 check (pcic_crosswalk.sh:182-184) reads `missing.txt`. The crosswalk's `no_series` (04_select.sql:113) reads absence from `pcic_outlet_daily`. | **Not covered.** The two sets agree only while `$SERIES` and `$DAILY` are kept or removed together. Finding 1. |

## Findings

- **[fragile, fails toward pass] extras/pcic_crosswalk/pcic_crosswalk.sh:182-184 (with :94, :150-151).**
  The guard on outlets with no series counts `$SERIES/missing.txt`. The crosswalk takes `no_series`
  from absence in `fwapg.pcic_outlet_daily` (04_select.sql:83, :113). These are two records of one set,
  and they live in different directories:
  - an outlet's empty CSV, written at :151, is in `$DAILY`;
  - the `missing.txt` line, written at :150, is in `$SERIES`.

  fetch_batch returns at :94 whenever the CSV exists, so it never rewrites `missing.txt`. A rerun after
  `$SERIES` alone has been removed therefore reads `n = 0` whatever the real count is. Simulated with
  150 single-outlet 422s:
  - the first run counts 150;
  - after `rm -rf $SERIES`, `n=0` and the guard passes.

  Removing `$SERIES` alone is a natural response to the guard's own message ("see
  $SERIES/missing.txt"). The comment at :90-91 says to remove both, but nothing enforces it. The run then
  places a crosswalk with every one of those outlets `no_series`. qa.sql's "placed >= 90%" test catches
  this only above about 4,800 outlets.

  Fix: count from the copy the crosswalk uses, after :190:

  ```sql
  SELECT count(*) FROM fwapg.pcic_outlets o
  WHERE NOT EXISTS (SELECT 1 FROM fwapg.pcic_outlet_daily q WHERE q.subid = o.subid)
  ```

  Keep `missing.txt` only as the list for a human to read.

- **[fragile, low, fails toward pass] extras/pcic_crosswalk/qa_gauges.sh:14-16, :85 with
  sql/qa_gauges.sql:67-74, :110-112, and review_build.sh:29-36, :45-47.** qa_gauges.sh says it "needs
  the run in pcic.discharge_monthly" but never checks for it. `fwa_annual` inner-joins the run and the
  final select left-joins it, so an absent run gives `q_fwa` NULL at every gauge, with no error. Two
  things follow:
  - `review_sample.sql:82` (`fwa_over_pcic NOT BETWEEN ...`) draws no gauge stratum;
  - review_build.sh passes as long as the stamp and the crosswalk md5 are unchanged.

  Sequence that reaches this:
  1. Build a run.
  2. Run load.sh against a published bundle that has the same run with a different fingerprint but the
     same crosswalk. load/pcic.sql:76-83 deletes the local rows. load.sh:190 reloads only the two
     hard-coded runs, so any other run stays absent. A listed run is reloaded instead, but from
     published rows built on other weights, and `pcic_qa_flow` still holds the local build.
  3. Run qa_gauges.sh.

  review_build.sh:33-36 justifies the md5-only stamp with "a crosswalk identical to the stamp's comes
  from the same deterministic build, and so does its discharge". That is the assumption R1 disproved for
  the export guard: the weights also depend on `fwa_watersheds_upstream_area`,
  `fwa_streams_watersheds_lut` and `blk_paths`. README:212 ("so not after `load.sh`") claims more than
  the code checks.

  The same unchecked LEFT JOIN is in qa_gauge.sh:74-76. It is a diagnostic, so a blank column is visible
  there.

  Fix, one mechanism for both triggers:
  - at :306, copy the run's `pcic.runs` fingerprint into the stamp (`weights_rows`,
    `weights_share_sum`, `monthly_rows`, `monthly_q_sum`);
  - have qa_gauges.sh refuse unless the `pcic.runs` row for its run equals the stamp, and the run's
    count in `pcic.discharge_monthly` equals `monthly_rows`;
  - have review_build.sh repeat the `pcic.runs`-row comparison.

- **[fragile, low, fails closed] load.sh:190.** The run list is a copy of the published `pcic.runs`'s
  membership, and nothing compares the two. The guard remedy that R2 wrote into both messages
  (pcic_export.sql:36, load/pcic.sql:51) is "delete their rows from pcic.runs, pcic.subbasin_daily and
  pcic.discharge_*". Following it for either PNWNAmet run and then publishing has two effects:
  - the uploaded `pcic.runs.csv.gz` omits that run;
  - its old per-run files stay on S3. The upload loop in extras/README.md:27 never deletes any.

  From then on every load.sh fails, at pcic_run.sql:46-47 ("the file's run is not in pcic.runs"). It
  fails closed, but only at every consumer's load, after the upload. In the other direction, a
  published run not in the list (any CMIP6 run) is listed in `pcic.runs` with no rows. README:285-288
  documents that.

  Fix:
  - before uploading, check that every run in load.sh's list is in the exported `pcic.runs` (a grep of
    load.sh against `pcic.runs.csv.gz` is enough);
  - or have load.sh check membership in `pcic.runs` and stop with a message that names the list.

## Round 2 fixes, checked

1. **Orphan check (pcic_export.sql:39-50, load/pcic.sql:53-64).** Correct. It enumerates all three
   per-run tables and excludes the incoming run or runs. The excluded runs are handled:
   - export: deleted, then re-inserted;
   - load: the stale-row deletes remove them, because no local `pcic.runs` row matches.
2. **Remedy messages.** They now name the tables. They do not mention load.sh's list or the published
   files (finding 3).
3. **`pcic_qa_gauges` run columns and review_build.sh:40-44.** Correct. `EXISTS match AND NOT EXISTS
   mismatch` refuses an empty or mixed table. `pcic_qa_build` is a one-row aggregate. What remains is
   that the gauges' FWA flow is not tied to the stamp (finding 2).
4. **README window SQL.** Correct. It is the same mapping as 01_days.sql:32, and the note is now true.
