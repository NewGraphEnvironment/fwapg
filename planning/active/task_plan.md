# Task: Publish PCIC crosswalk outputs to fresh-bc and load them in load.sh (#9)

## Problem
`extras/pcic_crosswalk` (#5, PR #6) exports `fwa_stream_networks_discharge_monthly.csv.gz` (40.5M rows, ~219 MB) and `pcic_fwa_crosswalk.csv.gz` (48,716 rows), but they are not published and `load.sh` does not read them. `load.sh` loads the other extras from upstream's `bchamp` object store; these outputs belong in NewGraph's `fresh-bc` bucket (`extras/README.md`).

What exploration found:
- The local files and fresh-db both match the issue's fingerprint, measured today: 40,524,444 rows, 3,377,037
  segments, sum 178035348.248310; 48,716 crosswalk rows.
- `s3://fresh-bc/fwapg/` already holds `dumps/` (a 13.3 GiB full DB dump), and the infra prefix policy grants
  `GetObject` on `<prefix>/*`. **Decided at this gate:** publish to `fwapg/extras/` and open only that prefix.
- The bucket policy is Terraform in NewGraph's private infra repo: `fresh-bc` → `public_read_prefixes = ["bcfishpass", "bcgw"]`.
  **Decided:** I open the infra issue and PR and run `tofu plan`; the user runs `tofu apply`.
- `load/fwa_*.sql` files follow `BEGIN; TRUNCATE; insert; COMMIT;`. The new load files use the same shape, so a
  failed download rolls back and leaves the table as it was.
- `db/schema.sql` is a pg_dump that is never hand-edited, and `db/migrations/` does not exist on `newgraph`.
  `load.sh` already loads the extras with `\copy FROM PROGRAM 'curl … | gunzip'`. The DDL goes in the load
  files (`CREATE TABLE IF NOT EXISTS`), so the fork's change stays in one block. The DDL repeats the job's
  (`pcic_crosswalk.sh:150`, `sql/pcic_crosswalk04_select.sql:27`). The COPY uses `HEADER MATCH` (PG 15+), so a renamed, added or reordered column fails the load rather than shifting values (code-check round 1: plain `HEADER` skips the line unchecked).
- **Decided:** verify in a scratch database plus an in-place reload rather than a full rebuild. fresh's
  `docker/load.sh` calls `db/create.sh`, which upstream removed in #193, so a full rebuild fails at stage 1.
- Branch off `newgraph` (repo CLAUDE.md), and open the PR with `--base newgraph`.

## Phase 1: Load files (test first)
- [x] Failing check first: running the load file into a scratch DB fails (the object is not uploaded or public yet)
- [x] `load/fwa_stream_networks_discharge_monthly.sql`: in one transaction, `CREATE TABLE IF NOT EXISTS` with the job's columns and PK `(linear_feature_id, month)`, `TRUNCATE`, then `\copy … FROM PROGRAM 'curl -sSf https://fresh-bc.s3.us-west-2.amazonaws.com/fwapg/extras/….csv.gz | gunzip' csv header`. `ANALYZE` afterwards.
- [x] `load/pcic_fwa_crosswalk.sql`: the same shape, with PK `subid` and the job's four indexes (`CREATE INDEX IF NOT EXISTS`, using the names Postgres gave the job's unnamed indexes so the in-place reload does not duplicate them)
- [x] `load.sh`: a "NewGraph fork only" section after the extras block that runs both files
- [x] Guard proof: with a bad URL, a reload of a populated scratch table fails and the row count is unchanged

## Phase 2: Publish
- [x] `aws s3 cp` both files to `s3://fresh-bc/fwapg/extras/`, then check with `s3api head-object` that the sizes equal the local files
- [x] Infra issue + PR: add `"fwapg/extras"` to `fresh-bc`'s `public_read_prefixes`; run `tofu plan` and confirm the only change is that bucket's policy; hand the user the bare `tofu apply` command. The infra issue links here; nothing in this fork names that repo or a host
- [x] After apply: an unauthenticated `curl -I` of both public URLs returns 200, and `fwapg/dumps/…` still returns 403
- [x] `extras/README.md`: point the PCIC and main-flow tree upload commands at `fwapg/extras/`, and say the PCIC outputs are loaded by `load.sh`

## Phase 3: Verify
- [x] Baseline: `qa_gauge.sh 08EE003` on fresh-db before the reload, saved to the job's `data/`
- [x] Scratch DB in the fresh-db container (`ltree`, schema `whse_basemapping`): run both load files and match the fingerprint (counts, distinct segments, sum to 6 dp, 48,716). Drop the scratch DB afterwards
- [x] In-place reload into `fwapg` on fresh-db: run both load files, match the fingerprint again, and check that `qa_gauge.sh 08EE003` output is identical to the baseline
- [x] `bash -n load.sh` and a check that the new section runs both files
- [x] File a fresh issue: `docker/load.sh` calls `db/create.sh`, which fwapg removed (upstream #193)

## Phase 4: Issue and docs
- [ ] Edit the #9 body: the prefix is `fwapg/extras/` and why (dumps), plus the verification method and its result
- [x] Note in `extras/pcic_crosswalk/README.md` where the outputs are published and that `load.sh` loads them

## Validation

- [ ] Tests pass (fingerprints match in the scratch DB and after the reload; gauge output unchanged)
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Out of scope, noted: `load.sh` does not load the main-flow tree either, and no issue covers that.
