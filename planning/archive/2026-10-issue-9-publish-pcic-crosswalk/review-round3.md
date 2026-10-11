# Review round 3: branch 9-publish-pcic-crosswalk-outputs-to-fresh (341b078...HEAD)

## Clean

No issues found.

## Mechanism behind rounds 1 and 2

Both rounds found the same shared assumption: **what COPY does on the target was taken from the server the work was tested on (fresh-db 17.5), not from COPY's documented contract across the range the repo says it supports.**
- Round 1: the author assumed `csv header` checks the header. On every version, it only skips the header line.
- Round 2: the author assumed `header match` exists. It does on 17 and 16, but not on the documented floor of 13 or 14.

Both are properties of the execution environment that were read off one environment. So the questions to ask are:
- Which properties of the server, the client and the tools does the new code rely on?
- Is each one true across the supported range, or guarded?

## Where that mechanism reaches in this diff

| Dependency | Where | Needs | Status |
|---|---|---|---|
| `HEADER MATCH` | both `load/*.sql` `\copy` lines | server 15+ | **Guarded** (load.sh:7, before any truncate). README floor updated |
| Parenthesised COPY options `with (...)` | both `\copy` lines | server 9.0+ | Below floor |
| `CREATE TABLE IF NOT EXISTS` | both load files | 9.1+ | Below floor |
| `CREATE INDEX IF NOT EXISTS` | pcic_fwa_crosswalk.sql:32-37 | 9.5+ | Below floor |
| `show server_version_num` | load.sh:7 | 8.2+ | Below floor |
| `TRUNCATE` inside `BEGIN` | both load files | always | Fine |
| `ltree` type, gist and btree opclasses | pcic_fwa_crosswalk.sql | the extension, installed by `db/schema.sql` | Fine (round 2 checked search_path) |
| psql client passes `\copy` options through verbatim | both `\copy` lines | any client in range | Fine, so client version is irrelevant (round 2 traced `parse_slash_copy`) |
| psql treats a nonzero `PROGRAM` exit as a `\copy` failure | truncated gzip case | client | Measured (round 2) with psql 17.5 and 18.6. The loader image is client 16, the same code path |
| `curl -f`, `gunzip` on the client | both `\copy` lines | tools | Loader image installs curl, and gzip is in the Ubuntu base. Round 1 measured empty input causing gunzip to exit 1 on Apple and Debian gzip |
| Public-read of `fwapg/extras/*` | URLs | bucket policy | Measured 200 (progress.md, 18:32Z) |

### Checking the enumeration in progress.md

The server-feature versions are right: 9.1, 9.5, 9.0, 15 and 8.2.

The entry "psql `\copy FROM PROGRAM` client 10" may be conservative. I believe psql's `\copy ... PROGRAM` came with COPY PROGRAM in 9.3, though I did not verify this. Either way it is below the floor, so the conclusion stands.

The enumeration covers server SQL features only, and omits the client and tool rows above. Rounds 1 and 2 measured those rows, so nothing is unhandled.

The only item above the documented floor is `HEADER MATCH`, and it is guarded.

The pre-existing upstream code is outside this diff. `db/schema.sql` was dumped by pg_dump 16.13, so its own floor was not re-derived here.

## The version guard (load.sh:7)

I tested it with a stub `psql` under `set -euxo pipefail`, on /bin/bash 3.2.57 and Homebrew bash 5.3.9:

| psql output | rc | Load reached? |
|---|---|---|
| `170005` | 0 | yes |
| `150000` | 0 | yes |
| `149999` | 1 | no |
| empty, psql failed (unreachable) | 1 | no |
| `abc` | 1 | no |
| `170005abc` | 1 | no |
| `99999999999999999999` | 1 | no |
| ` 170005` (leading space) | 0 | yes, which is correct |

- **Command substitution inside `[ ]`.** The exit status of the substitution is discarded, and the line's status is `[`'s. So a failed psql does not trip `set -e` there. Instead it produces an empty string, and `[ "" -ge 150000 ]` exits 2 ("integer expression expected"), which takes the `||` branch to `exit 1`.
- **Non-numeric or overflowing values** fail the same way. On every bad input the guard fails closed.
- **The `[` and `||` placement** keeps errexit from firing on the left side, so the explicit message prints.
- **`-X` matters.** It stops a `~/.psqlrc` from adding output that would make the value non-numeric (that would fail closed anyway). `-tA` gives the bare value with no padding.
- **The message on an unreachable server** says "needs PostgreSQL 15 or later", which is misleading. psql's own connection error prints just above it, so the cause is visible. This is not a defect.
- **The `-x` trace** echoes `$DATABASE_URL`, including any password in it, on this line. Every other `$PSQL` line in load.sh already does the same, so this is not new exposure from this diff.

The guard comes before the first `truncate` (load.sh:31), so a PG 13 or 14 server is refused before anything is touched. `db/schema.sql` runs before load.sh in the Quickstart. That is DDL only and is unaffected.
