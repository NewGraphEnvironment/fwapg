# Review round 1: branch 9-publish-pcic-crosswalk-outputs-to-fresh (341b078...HEAD)

## Findings

- **[fragile]** load/pcic_fwa_crosswalk.sql:30 and load/fwa_stream_networks_discharge_monthly.sql:18. The `\copy ... csv header` reads by position, and plain `HEADER` on input only skips the first line without checking the names in it. So the "drift fails loudly at the CSV HEADER copy" premise (task_plan.md, and the comment in both load files) holds only when the column count changes or a value cannot be cast. If the columns are reordered among compatible types, the load succeeds silently with values in the wrong columns. In `pcic_fwa_crosswalk`, seven columns are `integer` (subid, dowsubid, anchor_subid, fwa_parent_subid, depth, blue_line_key, candidate_rank), plus the bigint `linear_feature_id`. The same thing happens with the job's DDL as it stands: `CREATE TABLE IF NOT EXISTS` keeps an existing table whose column order differs from the CSV's.
  Measured on fresh-db (PG 17.5) with a temp table `t(a int, b int)` loading `b,a\n1,2`. `csv header` gives `COPY 1` with a=1, b=2 (swapped, no error). `with (format csv, header match)` gives `ERROR: column name mismatch in header line field 1: got "b", expected "a"` and psql exits 3. `HEADER MATCH` needs PG 15 or later. The servers here are fresh-db 17.5 and docker/db `postgis/postgis:16-3.5`, so it is available.
  Fix: `\copy <table> FROM PROGRAM '...' with (format csv, header match)` in both files. That makes the premise true.
  It does not fire today: the published CSV headers equal the DDL order, and on fresh-db the job-built tables' column order, PK and all six index names equal the load files' (checked via information_schema and pg_indexes).

## Checked and fine

- Failed download: `curl -sSf` writes nothing on a 403, and `gunzip` exits 1 on empty input, so COPY errors and the transaction rolls back. This holds for both Apple gzip 479 and Debian gzip 1.10 (in the container). A mid-stream drop truncates the gzip and also exits non-zero.
- Index names: `CREATE INDEX IF NOT EXISTS` names match what Postgres gave the job's indexes (`..._anchor_subid_idx`, `..._linear_feature_id_idx`, `..._wscode_ltree_idx` (gist), `..._wscode_ltree_idx1` (btree)), plus the two named ones from 06. A reload over the job-built table adds no indexes.
- The NULL, empty-ltree and float round-trip through `\copy TO ... CSV HEADER` and back with `csv` is lossless (an unquoted empty value reads as NULL, `""` as an empty string, and PG12+ float output is shortest-exact).
- `db/schema.sql` creates `whse_basemapping` and `ltree`, so the DDL works on a fresh database.
- Public-fork hygiene: no host, tailnet, credential or private repo name. Referenced repos `fresh` and `wet` are PUBLIC. The infra repo is described, not named.

## Notes (not defects)

- Until the bucket policy apply lands, `load.sh` on `newgraph` exits non-zero at this last section, after the multi-hour load and before the final `VACUUM ANALYZE`. That is the known pending state (Phase 2). Merge after the apply and the 200/403 `curl -I` check.
- findings.md records that `s3://fresh-bc/fwapg/dumps/` holds a 13.3 GiB full DB dump. The prefix is private and stays private under the `fwapg/extras/*` grant, so this is disclosure of a path, not of access.
