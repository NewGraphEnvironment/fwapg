# Progress — Publish PCIC crosswalk outputs to fresh-bc and load them in load.sh (#9)

## Session 2026-10-11

- Plan-mode exploration — phases approved by user
- Created branch `9-publish-pcic-crosswalk-outputs-to-fresh` off `newgraph`
- Scaffolded PWF baseline from issue #9 with approved phases
- Next: start Phase 1

- Phase 1: `load/fwa_stream_networks_discharge_monthly.sql` and `load/pcic_fwa_crosswalk.sql` (create if missing, truncate and `\copy` from `fresh-bc/fwapg/extras/` in one transaction), run from a fork-only section of `load.sh`
  - Failing check: scratch DB `fwapg_issue9`, load gives `curl: (22) … 403`, psql exits 3, and the table is rolled back (`to_regclass` NULL)
  - Guard proof: a populated table (1 row) keeps its row after a failed load; with `BEGIN`/`COMMIT` stripped, the same failure leaves 0 rows
- Phase 2: uploaded both files to `s3://fresh-bc/fwapg/extras/`; `head-object` sizes equal the local files (1,701,328 and 219,651,807 B)
  - Infra change opened in NewGraph's infra repo (one prefix added to the bucket's public-read list); `tofu plan`: 0 add, 1 change (the bucket policy gains `fresh-bc/fwapg/extras/*`), 0 destroy. Apply is the user's step
  - `extras/README.md` upload commands now target `fwapg/extras/` (the main-flow tree was not uploaded yet, so nothing moves)
- Phase 3 (partial): baseline `qa_gauge.sh 08EE003` saved to `extras/pcic_crosswalk/data/qa_gauge_08EE003_before9.txt` (gitignored); `bash -n load.sh` clean; filed NewGraphEnvironment/fresh#253 (loader calls removed `db/create.sh`; `FWA_StreamProfile` no longer in `schema.sql`)
- Phase 4 (partial): `extras/pcic_crosswalk/README.md` says where the outputs are published and that `load.sh` loads them
