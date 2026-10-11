<!-- Draft PR into smnorris/fwapg main from NewGraphEnvironment:upstream-blue-line-paths. NOT POSTED: needs approval. -->

## Blue line downstream paths (`extras/blue_line_paths`)

Adds a job that builds the downstream path of every FWA blue line: the chain of blue lines its water passes through to the sea, with the measure at which it joins each (`fwapg.blk_parents`, `fwapg.blk_paths`, `fwapg.blk_on_or_upstream()`).

Local watershed/local codes cannot order positions across blue lines (side channels, braids and code junctions that are not where a mouth is), so `FWA_Upstream` cannot answer "is b on or upstream of a" for an arbitrary pair. The paths answer it from geometry and codes together; the README lists how a line's parent and junction are chosen, in order.

This is a dependency of two further extras, sent as separate PRs stacked on this one: a PCIC streamflow crosswalk and a main-flow (dendritic) tree.

- `./blue_line_paths.sh`: builds the tables in one transaction (about 16 min province-wide on a local Docker database), then runs `sql/qa.sql` (3 tests: the Okanagan leaves BC and has no path; the Kitsumkalum reaches the Skeena through a braid; Cayoosh Creek reaches the Fraser through a side channel that touches nothing) and stops if any fails.
- Tested end to end, as committed, on a full provincial load (4,907,441 segments): 1,570,499 lines with a path.
