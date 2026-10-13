# Plan review (Plan agent, 2026-10-13): findings and dispositions

The reviewer found no blockers. It independently confirmed:
- the fixed body's md5 is `04ab3875…`, equal to the `postgisftw` copy and to the local DB's bodies;
- every callee has the same body in the local DB as in upstream `schema.sql`;
- `db/`, `docker/` and `.github/` are identical on `upstream/main` and `newgraph`, so the cherry-pick is clean;
- `test-migration.yml` has passed before (2026-04-17).

| # | Finding | Disposition |
|---|---|---|
| G1 | Commit messages are a leak path the plan didn't check: `(#N)` subjects would link to upstream's issue N, and the `Claude-Session:` trailer links to a private session | The upstream commits have no `(#N)`. The leak grep was widened (pattern below) and also run over `git log --format=%B`; it is clean except for the `Claude-Session:` trailer, which is **the operator's call** before posting |
| G2 | Insert the CTE at one anchor, not by a global replace (`postgisftw` already holds the same text) | Done: one insertion after `schema.sql:3884`, asserted in the script |
| G3 | Run `create_migration.sh` and `migrate.sh` from `db/` | Done |
| G4 | Set `DATABASE_URL` inline, never to the live `fwapg` DB | Done: inline, scratch DBs only |
| G5 | An empty DB takes the lake branch, so the scratch DB and CI never plan the non-lake query; check md5 equality | md5 recorded. The dummy-row behaviour test was skipped: the loaded-DB harness already shows the error-to-fix change. The limit is recorded in findings |
| G6 | The draft's repro needs a loaded DB | Taken into the draft |
| G7 | Use the byte-identity with `postgisftw` (and the fact that `pg_dump` emits `prosrc` verbatim) to answer "do not hand-edit" | Taken into the draft |
| G8 | Record the SQL used for the measurements, the rounding, and the line numbers at 8b3904e | Done in findings |
| O1 | Run `/code-check` on the upstream branch **before** pushing and cherry-picking | Adopted; the plan was reordered |
| O2 | `fix-exbc-nonlake` is not the only other copy of the text | Noted. Retiring it stays a step after the upstream PR is posted |
| A1 | The area test is partly circular | Recorded in findings |
| A2 | The scratch-schema copy is sound if only the header's function name is renamed | That is what was done |
| A3 | `CREATE OR REPLACE` must restate the attributes | It does (copied verbatim from `schema.sql`) |
| A4 | Timestamp ordering in `migrate.sh`; duplicate migrations if upstream re-timestamps | Recorded in findings |
| A5 | The group-shortcut case is unreachable under the current `load.sh` | Recorded in findings; goes in the draft |
| A6 | PG 17 locally, PG 16 in CI | Accepted; nothing here is version-sensitive |
| S1 | Keep the PR to the migration plus the hunk | As planned |
| S2 | No CI on the `newgraph` PR or the fork branch | Recorded in findings |

Leak pattern:

```
NewGraphEnvironment|newgraph|#[0-9]|fresh#|fresh/|fresh-bc|rtj|airvine|/Users/|localhost|b010209|docker_load
```

Commit messages are also checked for `claude\.ai`.
