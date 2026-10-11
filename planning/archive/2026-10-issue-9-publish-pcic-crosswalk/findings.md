# Findings — Publish PCIC crosswalk outputs to fresh-bc and load them in load.sh (#9)

## Issue context

**If we do it:** fresh-db (and any fwapg load) gets `whse_basemapping.fwa_stream_networks_discharge_monthly` and `whse_basemapping.pcic_fwa_crosswalk` without running the hours-long `extras/pcic_crosswalk` job. **If we never do:** the tables exist only where someone ran the job by hand.

## Problem
`extras/pcic_crosswalk` (#5, PR #6) exports `fwa_stream_networks_discharge_monthly.csv.gz` (40.5M rows, ~219 MB) and `pcic_fwa_crosswalk.csv.gz` (48,716 rows), but they are not published and `load.sh` does not read them. `load.sh` loads the other extras from upstream's `bchamp` object store; these outputs belong in NewGraph's `fresh-bc` bucket (`extras/README.md`).

## Proposed solution
- [ ] Upload both files to `s3://fresh-bc/fwapg/`, from the build of #14 (PR #21, merged as 341b078). Fingerprint: `fwa_stream_networks_discharge_monthly` 40,524,444 rows, 3,377,037 segments, `sum(round(q_m3s::numeric, 6))` = 178035348.248310; `pcic_fwa_crosswalk` 48,716 rows
- [ ] Open the `fwapg/` prefix for public read in the `fresh-bc` bucket policy (today only `bcfishpass/` is public). **Decided 2026-10-11: a public prefix**, so wet and other consumers can read the published files without credentials, and `load.sh` reads them like the `bchamp` extras.
- [ ] Create both tables in `load.sh` (or `db/` on `newgraph`) and load them from `https://fresh-bc.s3.us-west-2.amazonaws.com/fwapg/...` the way the `bchamp` extras are loaded
- [ ] Rebuild fresh-db and check row counts and one gauge (`extras/pcic_crosswalk/qa_gauge.sh 08EE003`)

The old annual table, `whse_basemapping.fwa_stream_networks_discharge`, and `fwa_streams.mad_m3s`, which is built from it, are left as they are: this adds tables and changes none. Consumers of `mad_m3s` (fresh) are unaffected.

## If the crosswalk goes upstream

#20 offers `extras/pcic_crosswalk` to smnorris/fwapg. The load step here is fork-only either way, but what it ends up being depends on how that goes:
- **Merged:** upstream's `load.sh` would likely load the outputs from `bchamp` like the other extras, and the `fresh-bc` copy and this fork's load step become redundant. Drop them then.
- **Merged with changes:** table or column names may move. Consumers that read these tables by name (NewGraphEnvironment/wet#59) follow.
- **Declined or stalled:** this load step is the only way the tables reach a database, and it stays.

#14 is done (PR #21). Not blocked by #8: that review gates sending the crosswalk upstream (#20), and any fix it leads to is a rerun and a re-upload here. NewGraph fork only (`newgraph` branch).

## Plan-mode measurements (2026-10-11, local fresh-db)

- fresh-db matches the issue fingerprint: `fwa_stream_networks_discharge_monthly` 40,524,444 rows, 3,377,037 segments, `sum(round(q_m3s::numeric, 6))` = 178035348.248310; `pcic_fwa_crosswalk` 48,716 rows. The local `.csv.gz` exports (2026-10-11 10:50) are from that build.
- `s3://fresh-bc/fwapg/` holds `dumps/` (a 13.3 GiB full database dump). The bucket's prefix policy grants `s3:GetObject` on `<prefix>/*`, so opening `fwapg/` would publish the dump. User decided: publish to `fwapg/extras/` and open only that.
- The bucket policy is managed in Terraform (private infra repo), not by the CLI. User decided: agent opens the change and runs plan; user applies.
- `db/schema.sql` is a pg_dump that is not hand-edited; `db/migrations/` does not exist on `newgraph`; the docker db image runs only `schema.sql`. DDL goes in the load files with `CREATE TABLE IF NOT EXISTS`.
- fresh's `docker/load.sh` runs `db/create.sh`, which was removed upstream in #193, so a full fresh-db rebuild through it fails at stage 1. User decided: verify in a scratch DB plus an in-place reload.

## Errors Encountered

| Error | Resolution |
|-------|------------|
