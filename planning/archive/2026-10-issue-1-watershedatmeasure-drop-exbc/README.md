## Outcome

Round 2 of #1. On smnorris/fwapg#199 the maintainer said dropping hydrosheds/NHD had been the intent of upstream PR 185, and asked for round 1 (restore the `exbc` CTE) to be redone by deleting the leftover `UNION ALL`. Scope chosen at the plan gate was Middle: every `exbc` CTE and branch is removed from both copies of `fwa_watershedatmeasure` (`whse_basemapping` and `postgisftw`, river and lake paths), so neither reads hydrosheds or NHD; the tables and functions stay (upstream issue 184). The change is migration `202610131654__watershedatmeasure_drop_exbc.sql` plus the same edit in `db/schema.sql`. It is on branch `watershedatmeasure-drop-exbc` off `upstream/main` (ad3815a, 2aad0d4, pushed to `origin`); the upstream PR text is drafted in `upstream_pr.md` and **not posted**. On `newgraph` it arrives as a revert of round 1 (f2aba13) plus cherry-picks, so `db/` equals the upstream branch.

The durable result, covering where cross-border area comes from and the three load eras of a db, is in `research/fwa_watershedatmeasure_xborder.md`.

## Measurement

- **Areas.** At the four test points (Bulkley, Kootenay R., Kootenay Lake, Columbia), the areas and geometries (`md5(ST_AsBinary)`) are byte-identical to the old function with `exbc`: 231944.70, 3469676.93, 4650676.78 and 8743886.64 ha. The three cross-border points each have 12,452.9 km² outside BC. This confirms the expected result, because the hydrosheds/NHD tables are empty on any load since PR 185, and it turns that expectation into a measurement.
- **Migration.** On scratch DBs it applies from upstream's `schema.sql`, re-runs as a no-op, keeps the COMMENTs, and is picked up by a db already at round 1's version (202610131450). The new `schema.sql` loads with 0 errors. Both copies end at md5 `d58003b9…`.
- **Code-check.** Three rounds. Round 2 found a defect inside round 1's fix: a remedy in the migration comment ("load the xborder file first") that cannot run on a db from before PR 185. Round 3 named the mechanism (statements about "a db" written from the one db that had been tested) and enumerated all 42 shipped claims; all were true.

## Evidence

`findings.md` "Round 2 results" and "Code-check"; `review-round*.md`.

Closed by: PR into `newgraph` from `1-watershedatmeasure-drop-exbc` (see #1). #1 stays open until upstream merges.
