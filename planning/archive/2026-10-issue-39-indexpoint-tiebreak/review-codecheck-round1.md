# Review round 1: indexpoint-tiebreak (staged diff)

## Checklist read
- code-check-infra.md: in full
- code-check-python.md: in full
- code-check.md: prose of all 14 H3s under `## Mechanisms` (tables skipped); the 23 other H3s not read
- code-check-shell.md: "psql does not interpolate `:'var'` inside a dollar-quoted string, and `\quit N` exits 0"; 66 other headings not read
- code-check-r.md: "Postgres row order is never fixed unless the query fixes it...", "An `information_schema` lookup by the literal table name misses what Postgres resolves"; 109 other headings not read
- code-check-spatial.md: "FWA `upstream_route_measure` misses the next segment's start", "A Freshwater Atlas main stem's downstream end lies on the receiving river's centreline...", "FWA main flow is not edge type 1000 alone"; 90 other headings not read

## Clean
No issues found.

## What was checked
- **Body matches schema.sql.** I diffed migration lines 18-96 against `db/schema.sql` 2373-2448. The only differences are `CREATE` -> `CREATE OR REPLACE`, the two ORDER BYs and two new comment lines. `CREATE OR REPLACE` keeps the existing `COMMENT ON FUNCTION`, the owner and the signature. The migration timestamp sorts after `202610131654`, and BEGIN/COMMIT follow the sibling migration.
- **SQL name resolution.** The inner ORDER BY, `blue_line_key, distance_to_stream, downstream_route_measure DESC, linear_feature_id`, ends on a key that is unique within the group. In the outer ORDER BY, `b.distance_to_stream` is the unrounded column, the bare `linear_feature_id` resolves to the output column (the same value), and WHERE still reads the unrounded `b.distance_to_stream`. The live server is PG 17.5, and the body compiles there (CREATE FUNCTION succeeded inside the transaction).
- **The test file on the live DB.** Before the migration it gives t,t,t,t,t,t,t,t,f,f. After the migration, inside BEGIN...ROLLBACK, all 10 are t. The live function's md5 was the same before and after the run (`ac5caf79...`), so nothing was committed.
- **Restoring the bug:** the second gauge test and the LocateAlong test fail on the old function. The first gauge test (blk 360886970 -> 5086970) already passes on the old function, because plan order happened to pick the right row. It is a valid pin, but on this database it does not prove the fix.
- **Mechanism at gauge 2 (blk 356360570).** Both candidates are at exactly 67.56368130037775 m. The old pick, 703862843 (f=1), returned 14040.005812552621, which is 2e-10 below the upper segment's `downstream_route_measure` of 14040.0058125527. Rounded to 4 dp, FWA_LocateAlong still selects the upper segment. It then returns no row because `ST_LocateAlong` gets a measure below that segment's start M, 14040.0058125527. The new pick returns its `downstream_route_measure` exactly.
- **What the fix relies on.** It needs the start-vertex M to equal `downstream_route_measure`. On a 5% TABLESAMPLE (244,962 non-6010 segments), they differ on 0 rows.
- **Population probe** (temp tables, in a transaction that was rolled back): 400 sampled main-stem segment start vertices, 4 offsets each (5-47 m, varied bearings), 1,600 points in all. FWA_LocateAlong found no point for the returned measure on 10 points before the fix and 1 after. The remaining failure is not a tie. The point is nearest the top end of the last segment of blk 356527183 (707510586, f=1), where `drm + length_metre` = 4096.596659 and `round(urm, 4)` = 4096.5967, so LocateAlong's half-open interval excludes it. That behaviour predates this diff and is outside its scope.

## Notes (not findings)
- The migration comment says the old measure "could fall short of the next segment's start, so FWA_LocateAlong found no segment for it". In the measured case LocateAlong did find the segment, through its 4-dp rounding filter. It returned nothing because `ST_LocateAlong` gets a measure below the segment's start M. The comment is accurate for shortfalls above 0.05 mm, which the 4-dp filter does reject. If the PR body repeats this mechanism, consider saying "found no point".
