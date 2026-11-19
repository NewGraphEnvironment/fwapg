# Code-check round 3: indexpoint-tiebreak (staged diff)

## Checklist read
- code-check-infra.md: in full
- code-check-python.md: in full
- code-check-r.md: "Postgres row order is never fixed unless the query fixes it..." only. The rest is R, DBI and arrow, none of which the diff uses.
- code-check-shell.md: "psql does not interpolate `:'var'` inside a dollar-quoted string, and `\quit N` exits 0" only. The rest is bash, git and gh, which the diff does not use.
- code-check-spatial.md: "FWA `upstream_route_measure` misses the next segment's start" and "A Freshwater Atlas main stem's downstream end lies on the receiving river's centreline". The rest is terra, sf and GDAL, which the diff does not use.
- code-check.md: the prose of all 14 H3s under `## Mechanisms`, with the table rows and evidence blocks skipped.

## Verdict
Clean. No defect found.

## Mechanism analysis (what a remaining defect would come from, and where it reaches)

**1. The fix assumes a measure exactly equal to a segment's `downstream_route_measure` falls on that segment for every consumer.** Each place this reaches was checked:
- The output measure for the chosen upper segment is exactly its drm: `ST_LineLocatePoint` returns 0 at the start vertex, and 0*len + drm = drm. Test 2 confirms it (14040.0058125527).
- `FWA_LocateAlong` filters on `round(drm,4) <= round(m,4) AND round(urm,4) > round(m,4)` and then takes drm DESC. With m = drm_upper the upper segment always qualifies, and wins whichever way urm_lower misses the next start. Across all 4,907,191 non-6010 rows, no segment has `round(urm,4) <= round(drm,4)`.
- `ST_LocateAlong(geom, drm)` needs the start M to equal drm. Across all 4,907,191 non-6010 rows, every `ST_M(ST_StartPoint(geom)) = downstream_route_measure` holds exactly, and `ST_LocateAlong(geom, downstream_route_measure)` is never empty.
- `FWA_WatershedAtMeasure` (`drm <= v_measure ORDER BY drm DESC LIMIT 1`, then `ST_LocateAlong`) picks the upper segment for the new measure. The old measure for test 2 (14040.005812552621) is empty under `ST_LocateAlong` on both segments 703862843 and 703862887, so the old row choice also broke WatershedAtMeasure there. The fix repairs it too.

**2. A tie has to be bit-exact for the new ORDER BY key to fire.** liblwgeom's `lw_dist2d_pt_seg` returns the vertex itself when r<0 or r>=1, and A + 0*(B-A) = A when r==0. So both segments give identical distances when the vertex they share is bit-identical. In BULK, HORS and PARS, all 52,687 adjacent same-blk pairs have bit-identical shared vertices (0 differ, 0 more than 1 mm apart). Every geometry is LineString (4,907,441 of 4,907,441).

**3. DISTINCT ON and ORDER BY determinism (code-check-r row-order rule).** The inner sort ends on `linear_feature_id`, which is NOT NULL and unique. `(blue_line_key, downstream_route_measure)` is NOT NULL and has 0 duplicates. A NULLS FIRST under DESC cannot reach a NULL. The outer sort also ends on `linear_feature_id`. The bare `linear_feature_id` resolves to the output column, which is b's value. `b.distance_to_stream` is the unrounded input column, as the comment says. The bare name would resolve to the rounded output column.

**4. Callers of whse_basemapping.fwa_indexpoint.**
- In `db/schema.sql` the only caller is `postgisftw.fwa_indexpoint` (schema.sql:325, `SELECT FWA_IndexPoint(pt.geom, $4, $5)`). It passes rows through and does not depend on row choice or column order.
- `RETURNS TABLE` is unchanged, so `CREATE OR REPLACE` keeps grants and comments, and `SELECT *` callers see the same columns in the same order.
- No other migration and no tracked file outside docs and tests call it (`git grep -i indexpoint`).
- On the loaded DB, `pg_depend` shows no views, matviews or indexes on it, and the only other `prosrc` that mentions it is the postgisftw wrapper.
- The docs examples (docs/01_usage.md, 03_functions.md) use LATERAL with `num_features` 10 and do not depend on tie order.

**5. Migration mechanics.**
- The function body is byte-identical to schema.sql 2373-2448 apart from `OR REPLACE`, the two ORDER BYs and two comment lines (diffed).
- BEGIN/COMMIT matches the prior migration, and the timestamp 202610240132 sorts after 202610131654.
- The CI image (`docker/db/Dockerfile`) loads schema.sql, so the LANGUAGE sql body validates against existing tables.
- I applied the migration in a transaction that ended in ROLLBACK and ran tests/test_FWA_IndexPoint.sql: all 10 rows returned `t`.

**6. Restore-the-bug.** Run against the old (loaded) function:
- New test 1 passes (5086970, by plan order). This is the accepted pin.
- New test 2 fails: it returns 703862843.
- The LocateAlong test fails: count 0.

So both new guards fire on the defect.

## Non-defect note for the PR text (a behaviour consequence, not a code issue)
At a vertex where a tributary joins, the tie choice also decides whether that tributary is upstream of the snapped point. Measured at the test 1 vertex with the 4-arg `fwa_upstream`:
- Lower segment 5086038 (localcode `400.536025.367117`): tributary 360814623 (wscode `400.536025.369337`) is upstream. The upstream length within the group is 339,382 m.
- Upper segment 5086970 (localcode `400.536025.369337`): the tributary is excluded ("exclude trib at the same position"). The upstream length is 333,955 m.

The new choice is the same answer `FWA_WatershedAtMeasure` and `FWA_LocateAlong` already give for a measure at that vertex, so it is consistent with the [downstream, upstream) convention. Before the fix the answer was plan-order dependent. Code-based consumers of the returned wscode and localcode (`FWA_Upstream` and `FWA_Downstream`) will now consistently exclude the tributary joining at the snapped vertex. Data already written from the old function (event tables in downstream projects) keeps whichever segment the old plan picked. One sentence in the PR would let consumers know.
