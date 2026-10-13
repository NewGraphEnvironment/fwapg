# Code-check round 3: cherry-picking the fix onto `newgraph`, and where the "accidental" assumption still sits

Reviewer: subagent, 2026-10-13. Scope:
- carrying d222a91 and fc63f79 (on `fix-watershedatmeasure-exbc`, based on upstream/main 8b3904e) onto `newgraph`;
- every place in committed or published text that still treats the #185 removal as accidental.

## Findings

The code is clean for `newgraph`. All the findings are text, and all come from the same mechanism as round 1's finding: the text says #185 removed the CTE by accident, and #185's own commit message says the opposite ("do not load nhd or hydrosheds", "update fwa_watershedatmeasure to use new xborder data"). The commit messages, the migration header and `upstream_pr.md` are already neutral. The places below are not.

- **[fragile]** NewGraphEnvironment/fwapg#1 body, line 3 (Problem): "PR #185 "Xborder" ... **accidentally removed** the `exbc` CTE". This is published text in a public repo. It asserts an intent that the evidence contradicts. The upstream draft now says "dropping the CTE looks intended", so the issue and the PR that will cite it disagree. Edit the body (feature-workflow, "Issue bodies get edited, not appended").
- **[fragile]** NewGraphEnvironment/fwapg#1 body, line 63 (Plan): "Fix option 1 above (restore the CTE): **an exact revert of an accidental deletion** ... Option 2 (drop the `exbc` branches) stays with upstream issue 184." There are two problems here:
  - the same "accidental" assumption;
  - the plan is now stale. The upstream draft offers option 2 in the PR itself ("happy to switch to option 2"), so option 2 no longer "stays with #184".
- **[fragile]** NewGraphEnvironment/fwapg#1 body, line 85 (Plan): "Cherry-pick rather than re-edit, so that when `newgraph` later merges upstream's version **the two changes are identical and do not conflict**." That only holds if upstream merges option 1 unchanged. The draft now invites option 2, so this is the same "upstream agrees with our framing" assumption, one step on.
  - I reasoned this out and did not run it. If upstream instead removes the `UNION ALL ... FROM exbc` branch in `agg` with its own migration, then merging upstream into `newgraph` probably still applies textually: the CTE insertion (~schema.sql:3885) and the `agg` branch (~3929 before the fix) are about 40 lines apart.
  - The result would not be identical, though. `newgraph`'s `schema.sql` would keep an unreferenced `exbc` CTE. A DB that ran both migrations would have upstream's body, so a fresh install and a migrated DB would hold different function text. They would behave the same, because the CTE is never read.
  - The sentence should be conditional on upstream taking option 1. The line also says "cherry-pick its commit", but there are two commits.
- **[fragile]** `planning/active/task_plan.md:5` and `planning/active/findings.md:7`: "accidentally removed". `findings.md:67`: "an exact revert of an accidental deletion". These are copies of the issue body. They are on the PR branch (`1-fwa-watershedatmeasure-exbc-cte-missing`, not yet pushed), so they become public in this fork when the `newgraph` PR opens, and again when `/planning-archive` copies them into `planning/archive/`. Fix them together with the issue body.
  - `findings.md:123`, "The fix is an exact revert", states a fact about the text and is correct (the md5 matches the pre-#185 body). It is not a finding.
- **[fragile]** `origin/fix-exbc-nonlake`, commit 4708405. This is a public branch on the fork. Its message says "PR #185 (Xborder) **accidentally removed** the exbc CTE". It also gives the scope wrongly: "This caused cross-border watershed delineation to fail for river/canal points upstream of international or interprovincial borders". In fact every non-lake call fails; the issue's Bulkley measurement shows it. The message also carries "Fixes NewGraphEnvironment/fwapg#1".
  - Commit messages are not rewritten, so the remedy is the one the issue's plan already has: delete the branch (`git push origin --delete fix-exbc-nonlake`) once the `newgraph` PR is open.
  - Until then, do not cite it, and do not pick it by mistake for either PR.

No other committed or published text carries the assumption:
- the d222a91 and fc63f79 messages say "deleted"/"removed" and "Restores the CTE as it was before that change";
- the migration header (lines 3-6) says "removed its definition but kept the reference";
- the `upstream_pr.md` body says "dropping the CTE looks intended";
- the planning-branch commit subjects (7748f5a..eefb994) are neutral;
- the issue title says "(xborder regression)", which is accurate either way, since calls error.
- `git grep -i accident` on origin/newgraph (excluding CLAUDE.md) is empty.

## Checked and clean (the `newgraph` side)

- **Clean cherry-pick.**
  - `git merge-base upstream/main newgraph` = 8b3904e = upstream/main, so `newgraph` contains all of upstream main.
  - `git diff --stat upstream/main newgraph -- db/ docker/ .github/` is empty.
  - In a throwaway clone, `git cherry-pick d222a91 fc63f79` onto origin/newgraph applied with no conflict. `diff <(git diff origin/newgraph HEAD) <(git diff 8b3904e fix-watershedatmeasure-exbc)` was identical.
  - Resulting blobs:
    - `db/schema.sql` 9eb8bb25…;
    - the migration 52403bc0…;
    - both equal the blobs on `fix-watershedatmeasure-exbc`.
  - The planning branch (HEAD) has origin/newgraph as an ancestor, and its own commits touch only `planning/`. Cherry-picking onto it is equivalent.
- **No dependency on newgraph's fork-only files.** The fork-only diff covers 120 files: `extras/` (37), `load/` (2), `load.sh`, `README.md`, `CLAUDE.md`, `research/`, `.claude/` and `planning/`. In it:
  - nothing references `fwa_watershedatmeasure`, `exbc`, `hybas_lev12_v1c`, `wbdhu12`, `hydrosheds`, `usgs`, `fwapg.db_version`, `migrate.sh` or `db/migrations`;
  - nothing in `load.sh`, `load/` or `extras/` creates or replaces that function;
  - the only `CREATE OR REPLACE FUNCTION` is `fwapg.blk_on_or_upstream` in `extras/blue_line_paths/sql/blue_line_paths.sql`, and it does not collide.
- **Migrations on newgraph.**
  - `load.sh` (upstream's lines plus the PG15 guard and the PCIC loads) never runs `migrate.sh` or touches `fwapg.db_version`.
  - `test-migration.yml` fires only on PRs into `main`, so the `newgraph` PR runs no migration CI. That matches CLAUDE.md, and is not a gap introduced here.
  - On a DB without `fwapg.db_version`, `migrate.sh` bootstraps `'0'` and applies this one idempotent migration.
- **A newgraph DB built from `schema.sql` + `load.sh` gets the fixed function.** The function is defined only in `schema.sql`, and the blob is identical to the one round 2 loaded with `ON_ERROR_STOP` (prosrc md5 `04ab3875…`). fresh's loader on its open branch for fresh#253 (PR 254) runs `$PSQL -f db/schema.sql` from the mounted fwapg checkout, so it picks the fix up once that checkout is on `newgraph`.
- **Operational note, not a defect.** Two cases are not fixed by merging into `newgraph`:
  - an already-loaded DB, which needs `psql -v ON_ERROR_STOP=1 -f db/migrations/202610131450__fix_watershedatmeasure_exbc.sql` (or `db/migrate.sh`);
  - the published `fwapg-db:main` image, which builds `schema.sql` from `main`.

  Both are worth one line in the `newgraph` PR body, in the same spirit as CLAUDE.md's note about the loader image.

The scratch clone used for the cherry-pick test (in the session scratchpad) was deleted. No scratch DB was needed, because the blobs are byte-identical to what round 2 loaded.
