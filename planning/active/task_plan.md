# Task: FWA_WatershedAtMeasure: exbc CTE missing from non-lake path (xborder regression) (#1)

## Problem

PR #185 "Xborder" (upstream `smnorris/fwapg`, merged 2026-01-16) accidentally removed the `exbc` CTE from the non-lake code path in `FWA_WatershedAtMeasure`, while keeping the reference to it in the `agg` CTE at line 329.

**Every non-lake call fails, not only cross-border points.** PL/pgSQL plans the whole `RETURN QUERY` statement, so the undefined `exbc` is an error at any point the non-lake branch handles. Measured 2026-10-12 on a database built from `db/schema.sql` at NewGraphEnvironment/fwapg@b010209 (NewGraphEnvironment/fresh#253's loader run, evidence `fresh/data-raw/logs/docker_load_253/`):


Full issue body (with its plan and measurements) is in `findings.md`.

## Branch layout
- **`fix-watershedatmeasure-exbc`**, off `upstream/main`, pushed to our fork. It is the upstream PR's head and holds exactly two commits: the migration, then `schema.sql`. Its commit messages carry no NGE issue numbers, links or paths.
- **`1-fwa-watershedatmeasure-exbc-cte-missing`**, off `newgraph`. It holds:
  - the planning (PWF) baseline;
  - the two commits, cherry-picked;
  - the upstream PR draft;
  - the archive.

  It is opened as a PR into `newgraph`.

## Phase 1: The fix, on the upstream branch
- [x] Branch `fix-watershedatmeasure-exbc` off `upstream/main` (confirm its head is still 8b3904e, or note what moved).
- [x] Migration `db/migrations/<ts>__fix_watershedatmeasure_exbc.sql`, created with `db/create_migration.sh`. Inside `BEGIN`/`COMMIT`: `CREATE OR REPLACE FUNCTION whse_basemapping.fwa_watershedatmeasure(...)`, taking the body extracted from `schema.sql:3630` onward (signature, language and attributes unchanged) with the `exbc` CTE inserted before `agg`. Commit.
- [x] Make the same CTE insertion in `db/schema.sql`. Then check:
  - the diff from `upstream/main` is exactly those lines;
  - the migration's function body equals the edited `schema.sql` body byte for byte, as a script check rather than by eye.

  Commit.

## Phase 2: Test
- [x] Behaviour, in the loaded local database. Create `exbc_test.fwa_watershedatmeasure` twice: once from the fixed body, and once (under a different name) from the unfixed `upstream/main` body. Run four calls against the fixed one:

  | call | expect |
  |---|---|
  | (360873822, 166030) Bulkley | 231944.7 ha |
  | (356570348, 160000) Kootenay R. | 3469676.9 ha, 12452.9 km² outside BC |
  | (356570348, 110000) Kootenay Lake | 4650676.8 ha |
  | (356570372, 1203700) Columbia | 8743886.6 ha |

  The unfixed one must raise `relation "exbc" does not exist` at the Bulkley point. Also diff the fixed body against the local database's own `whse_basemapping` body (the pre-PR 185 version) and record what differs. Then drop `exbc_test`. If the newer body calls something the old database lacks, record it, and test in the scratch database below instead.
- [x] Migration path, as CI does it:
  - Create a scratch database `fwapg_exbc_test` on the local server and load `upstream/main`'s `schema.sql` into it.
  - Run `migrate.sh --dry-run`, then `migrate.sh`.
  - Assert three things: the function's `prosrc` contains `exbc AS` twice; `fwapg.db_version` holds the migration's timestamp; a second run says "up to date".

  Then drop the scratch database. This touches no data the PCIC job uses.
- [x] Record the results table and commands in `findings.md`.

## Phase 3: `newgraph` PR and upstream draft
- [ ] `/code-check` on the upstream branch (`upstream/main..fix-watershedatmeasure-exbc`) **before** pushing or cherry-picking (plan review O1), plus the widened leak grep over the diff **and** the commit messages (G1).
- [ ] Push `fix-watershedatmeasure-exbc` to `origin` (the fork). Open no PR from it yet.
- [ ] On the PWF branch, cherry-pick both commits. The `newgraph` diff must equal the upstream branch's diff.
- [ ] Write `planning/active/upstream_pr.md`, the upstream PR draft. It covers:
  - the title;
  - the repro (any non-lake point on a fresh install), pinned to 8b3904e;
  - the deleting commit (3c43bdd, upstream PR 185);
  - the test table;
  - why `schema.sql` is hand-edited against `db/README.md`, with an offer to drop that commit;
  - upstream issue 184 as the alternative.

  It contains no NGE issue links, hosts or private repos.
- [ ] `/code-check branch`, then archive the planning files, then `/gh-pr-push` the PWF branch with `--base newgraph -R NewGraphEnvironment/fwapg`. The PR body says it carries the same two commits as the pending upstream PR and links #1.
- [ ] Tick the matching boxes in #1's body. #1 stays open (a `newgraph` merge doesn't close it), and is closed when upstream merges or declines.

## Not in this run
- **Posting the upstream PR** waits for your approval of the draft. Then: `gh pr create -R smnorris/fwapg --base main --head NewGraphEnvironment:fix-watershedatmeasure-exbc`.
- **Merging the `newgraph` PR** needs a separate instruction.
- **Retiring `fix-exbc-nonlake`** (local and remote) happens after the upstream PR is posted, since until then it's the only other copy of the text.
- **The group-shortcut case** (cross-border area dropped where `fwa_watershed_groups_poly` has codes) stays unmeasured, as the issue says.

## Validation

- [ ] The four expected areas reproduce, and the unfixed body errors in the same harness.
- [ ] The migration applies on a fresh `schema.sql` database, is recorded in `db_version`, and is a no-op on a re-run.
- [ ] The upstream branch's diff from `upstream/main` is only the migration file plus the CTE lines in `schema.sql`. The PWF branch's diff, outside `planning/`, is the same.
- [ ] `grep -rnE 'NewGraphEnvironment|fwapg#|fresh-bc|rtj' ` over the upstream branch's diff and the draft comes back empty.
- [ ] `/code-check` clean (`/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
