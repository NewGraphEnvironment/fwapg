## Outcome

Upstream PR 185 removed the `exbc` CTE from the non-lake path of `whse_basemapping.fwa_watershedatmeasure` but kept the `UNION ALL ... FROM exbc` branch in `agg`. Every non-lake call on a database built from the current `schema.sql` therefore fails with `relation "exbc" does not exist`.

The fix restores the CTE, as the repo's first migration (`db/migrations/202610131450__fix_watershedatmeasure_exbc.sql`) plus the same 16 lines in `db/schema.sql`. Afterwards the function body is byte-identical to the `postgisftw` copy and to the body before PR 185.

It is on two branches:
- `fix-watershedatmeasure-exbc`, off `upstream/main`, pushed to the fork. This is the head of the upstream PR, drafted in `upstream_pr.md` and **not posted**.
- This branch, cherry-picked, as a PR into `newgraph`.

Code-check round 1 established something the plan had wrong. PR 185's own notes suggest the CTE was dropped on purpose ("do not load nhd or hydrosheds"); the leftover branch is the bug. So the upstream draft offers both fixes, restore or delete the branch, which give the same result on a standard load. The "accidental" wording was removed from the #1 body and the planning files.

Closed by: PR into `newgraph` (see #1); #1 stays open until upstream merges or declines.

## Measurement

**md5 of `prosrc`.** The fixed body, the `postgisftw` copy and the pre-PR 185 body are all `04ab3875b15e4cbf10a413be7acfb1e5` (18,883 chars). The unfixed body is 18,206 chars. This turned "restore the CTE" from a reconstruction into a proven exact revert.

**Areas.** With the fixed body in a scratch schema of the loaded local DB, the four expected areas reproduce:

| point | area (ha) |
|---|---|
| Bulkley | 231944.70 |
| Kootenay R. | 3469676.93 |
| Kootenay Lake | 4650676.78 |
| Columbia | 8743886.64 |

The three cross-border points each have 12,452.9 km² outside BC. The unfixed body raises the error, and the four calls took 35 s.

**Migration.** On scratch DBs built from `schema.sql`, the migration applies, records version 202610131450, re-runs as a no-op and keeps the function comment. The fixed `schema.sql` loads cleanly.

**Limit.** An empty database takes the lake branch, so CI's `test-migration.yml` proves only that the migration parses and applies, not the fix.

## Evidence

- `findings.md`, section "Phase 1–2 results": the SQL and the results table.
- `review-plan.md` and `review-round1.md` to `review-round3.md`: the reviews and their dispositions.
