## Checklist read
- code-check-infra.md: in full
- code-check-python.md: in full
- code-check.md: prose of all 14 H3s under `## Mechanisms` (table rows skipped); no other headings read, since none of the "Rules that stand alone", Security or PDF headings touch a SQL-function migration
- code-check-spatial.md: 3 headings read ("A Freshwater Atlas main stem's downstream end...", "FWA `upstream_route_measure` misses the next segment's start", "FWA main flow is not edge type 1000 alone"); the rest not read, as they cover terra/sf/GDAL/etc.
- code-check-r.md: 2 headings read ("Postgres row order is never fixed unless the query fixes it...", "An `information_schema` lookup by the literal table name..."); the rest not read, as they are R-specific
- code-check-shell.md: 1 heading read ("psql does not interpolate `:'var'`... and `\quit N` exits 0"); the rest not read, since the diff contains no shell, git or gh code

## Clean
No issues found.

## What I checked (a loaded fwapg; the migration was applied only inside a transaction that was rolled back)
- The function body matches db/schema.sql 2373-2448 except for the two ORDER BYs and the comments (diffed). `CREATE OR REPLACE` keeps the signature, the return type and the COMMENT ON FUNCTION.
- Determinism: the inner key `(blue_line_key, distance_to_stream, downstream_route_measure DESC, linear_feature_id)` and the outer key `(b.distance_to_stream, linear_feature_id)` both end on linear_feature_id, which is unique, so neither pick can tie.
- The outer-ORDER BY comment is true. In Postgres a bare name in ORDER BY resolves to the output column first, so the old `distance_to_stream` sorted on the ROUND(...,3) value. `b.distance_to_stream` is the unrounded input column. `WHERE distance_to_stream <= $2` was already the input column.
- Tests: on the old function, 8 t and then f, f (the second gauge test and the LocateAlong test). With the migration applied in a transaction, all 10 return t.
- The header's mechanism holds on the data. At 356360570 the lower segment 703862843 has dsm+length = 14040.005812552621. That is 1e-10 below the next segment's dsm and the M at its start vertex (14040.0058125527). LocateAlong's 4-dp rounded filter selects the upper segment, then ST_LocateAlong on that segment's geometry finds nothing below its starting M, and the lower segment's upstream_route_measure (14040.00493) excludes it. So no point is returned, exactly as described. At 360886970, dsm+length equals the next dsm to the float, which is why the first gauge test passes on the old function.
- "The measure returned is its downstream_route_measure" and "the measure returned at a vertex is one FWA_LocateAlong can find" hold beyond the test cases. Across all 4,907,191 non-6010 segments: the start M equals downstream_route_measure exactly at 0 exceptions, every geometry is a LINESTRING, and none is shorter than 0.2 mm. So measure = dsm_B + 0*len always passes LocateAlong's filter and lands on the start vertex's M.
- "(here the segment above a tributary)" is true. At both vertices a 1450 connector of another blue_line_key starts there: 360814623 at 5086970's start, and 356302336 at 703862887's start.
- Both distances tie bitwise (39.33023909369014 for both segments; 67.56368130037775 for both).

## Note (wording, not a defect)
- tests/test_FWA_IndexPoint.sql:32 says "a point equidistant from two segments of one stream, on the vertex they share". The migration's inner comment says "a point on a vertex two segments share". The test points are 39.3 m and 67.6 m from the stream, and their nearest point on both segments is the shared vertex. The header's own wording, "A point nearest the vertex two segments of one stream share", is the accurate one. The other two read as if the input point sits on the vertex: true of that narrower case, but not of the case being tested. Optional rewording: "a point whose nearest point on both segments is the vertex they share".
