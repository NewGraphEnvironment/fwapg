# Review round 2: branch 9-publish-pcic-crosswalk-outputs-to-fresh (341b078...HEAD)

## Findings

- **[fragile]** load/pcic_fwa_crosswalk.sql:29 and load/fwa_stream_networks_discharge_monthly.sql:18, against README.md:21. `HEADER MATCH` needs a PostgreSQL 15 or later **server**. The fork's README still states the requirement as "PostgreSQL (>13)", so PG 14 is documented as supported. On a 14 server, `ProcessCopyOptions` reads `header` with `defGetBoolean`, so the COPY fails with `header requires a Boolean value`. The failure is loud: psql exits 3, and the transaction rolls back, including the `CREATE TABLE IF NOT EXISTS`. But it comes at the very end of `load.sh`, after the multi-hour upstream load has committed. `load.sh` then exits non-zero, neither table exists, and the final `VACUUM ANALYZE` is skipped. No current NGE target is affected: fresh-db is 17.5 and docker/db is `postgis/postgis:16-3.5`. Fix: state PG 15+ for this fork, in the README requirement line or in the fork-only section's comment in `load.sh`. Or accept it and say so.

## The HEADER MATCH fix itself: works as intended

- psql's `\copy` does not parse the options. `parse_slash_copy` takes everything after the filename or `PROGRAM '...'` verbatim (`after_tofrom`) and sends `COPY <table> FROM STDIN <options>`, so the server checks the header and the psql client version does not matter. That covers the loader image's `postgresql-client-16` and any other client.
- I measured it with a TEMP table `t(a int, b int)` and gzip fixtures through `\copy t FROM PROGRAM 'cat x.gz | gunzip' with (format csv, header match)`. I ran it twice against the fresh-db server (17.5): with psql 17.5 inside the container and with psql 18.6 on the host. Both clients behaved the same:
  - correct header: `COPY 1`
  - swapped columns: `column name mismatch in header line field 1: got "b", expected "a"`
  - an extra column, or a missing one: `wrong number of fields in header line: got 3 (or 1), expected 2`
  - a quoted header `"a","b"`: accepted (the names are compared after dequoting)
  - a case change `A,b`: rejected (the comparison is case-sensitive, which is right: the job exports lowercase names)
  - empty input (as after a 403): rejected, and psql also reports the program's exit 1
- Truncated gzip, the case the header check cannot catch. When a download dies mid-stream after the header has passed, gunzip emits every complete row and then exits 1, so the server reports `COPY 2` (success). The rollback therefore depends on psql seeing the pipeline fail. I measured it: `BEGIN; TRUNCATE; \copy ...; COMMIT;` under `-v ON_ERROR_STOP=1` printed `COPY 2`, then `child process exited with exit code 1`, then psql exited 3 before reaching `COMMIT`, so the transaction is discarded on disconnect. The explicit `BEGIN` is what protects this case, not `HEADER MATCH`.
- A server-16 COPY was not exercised directly. `HEADER MATCH` has been documented since 15, and nothing here relies on behaviour that changed between 15 and 17.

## Where "the file is checked against the table" still does not hold (notes, not defects)

- **Names and count only.** `HEADER MATCH` checks the header line's names, their order and how many there are. Types are checked only by the input casts. So if a column keeps its name and changes meaning, for example units or a renumbered `month`, it loads silently. That is inherent to COPY.
- **Nothing checks that the two files come from the same build.** They are separate objects, loaded in separate transactions, and `fwa_stream_networks_discharge_monthly` is derived from the crosswalk placement. Two cases follow:
  - If someone re-uploads only one file after a rerun, the pair is mismatched with no signal. Today only the README's "upload both files again" guards against that.
  - On an in-place reload, if the crosswalk commits and the monthly download then fails, the database holds the new crosswalk and the old monthly flow. `load.sh` exits non-zero there, so the failure is visible, and a rerun repairs it.
- **Index names only.** `CREATE INDEX IF NOT EXISTS` matches by name, not by definition. An existing index of the same name on other columns would be kept silently. Round 1 confirmed that the names and definitions match the job's on fresh-db.

## Checked and fine

- `load.sh` runs the files by relative path (`load/$table.sql`), the same as the existing sections. The compose loader mounts the repo at the working directory, so `load/` is present even though the loader Dockerfile copies only `extras`, `.env.docker` and `load.sh`.
- The DDL's column order and the six index names and columns match the job: `pcic_crosswalk04_select.sql:27-43,124-127`, `06_subbasins.sql:116,158`, and `pcic_crosswalk.sh:150-156`. The job exports with `\copy <table> TO ... CSV HEADER`, so the header is the table's own column order.
- The unqualified `ltree` resolves: `db/schema.sql` installs it in `public`, and both the docker search_path and the default search_path include `public`. The existing `load/fwa_basins_poly.sql` uses unqualified `::ltree` as well.
- Public-fork hygiene in the new text: no host, tailnet, credential or private repo name.
