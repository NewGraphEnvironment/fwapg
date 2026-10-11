# Review round 2: SSNbler fix-pdist-precision-parallel-unsnapped vs upstream/develop (d3918f1)

HEAD 6ebcc90. All probes ran in copies under the session scratchpad (`git archive` of d3918f1 and
HEAD). /Users/airvine/Projects/repo/SSNbler was not modified.

## Findings

- **[severity: fragile, a false claim]** NEWS.md:5, R/dist_xy.R:3-5, commit fe18b57: "spacing at 1e6
  is 0.0625, so at projected coordinates (~1e6 m) it returns 0 for points up to ~6 cm apart" only
  holds for coordinates between 2^19 and 2^20 (524,288 to 1,048,576 m). Float spacing doubles at
  each power of two, so it understates the reach of the bug for much of the data it describes.
  Measured with pdist 1.2.1, giving the largest separation that pdist returned as 0 over 200
  random base points:
  - along x at 1e6: 0.0605 m (spacing 0.0625). The claim holds here.
  - along y at y = 1,261,000, **the test's own pinned northing**: 0.123 m (spacing 0.125).
  - along y at a UTM northing of 5.5e6: 0.497 m (spacing 0.5).
  - 50.2% of BC's land area (bcmaps::bc_bound, 2e5 samples) has a BC Albers northing above 2^20,
    where the limit is ~12.5 cm, not ~6 cm.

  For the upstream maintainer's users (UTM, or USA Albers with |x| up to ~2.3e6 and spacing 0.25
  m), "up to ~6 cm" understates the error 4 to 8 times. That matters in the document they will use
  to judge severity and whether to backport. Suggested wording: "float spacing is 0.0625 m at 1e6
  and doubles with each power of two (0.125 m above 1,048,576 m, 0.5 m at UTM northings), so pdist
  returns 0 for points that far apart."

- **[severity: fragile, a false claim]** commit fe18b57, message body: "the error grows with the
  coordinates (~1 cm at 2e5)". Float spacing at 2e5 is 2^-6 = 0.015625 m. The largest separation
  measured as 0 at 2e5 is 0.0155 m, so ~1.6 cm. The session's own findings.md records "1.6 cm at
  2×10⁵". The number in the commit message was mistyped from that, and "~1 cm" understates it by
  about a third. The branch has not been merged yet, so the message can still be reworded. Say
  "~1.6 cm at 2e5".

- **[severity: fragile, minor imprecision]** NEWS.md:6, "within each 500-node chunk only". In
  get_pdist_nodes(), 500 is a cap, not the chunk size. `chunk.no = ceiling(n / max.rows)` and then
  split_matrix() balances the rows across the chunks, so 701 nodes give 351 + 350 (the test
  comment says so itself). `max.rows = floor(2.8e8 / nrow(other_xy)) / 2` drops below 500 once
  there are more than 280,000 edges. The conclusion is right, but the stated size is wrong.
  Suggest "within each chunk of up to 500 nodes".

## Claims verified true (measured)

- pdist is single precision. pdist/R/pdist.R passes `as.single()` vectors through `.C`, and
  src/pdist.c works in `float` throughout. The subtraction is exact on the rounded inputs
  (Sterbenz), so all of the error comes from rounding the inputs. The commit says "its C code
  converts to float". Strictly, the R wrapper marks the inputs single and `.C` converts them, but
  "single precision" is accurate.
- Spacing at 1e6 is 0.0625, and pdist reads ~6 cm as 0 along x at 1e6 (0.0605 m measured).
- "~63% of random positions in BC Albers" (test comment, line 86) is roughly right. It depends on
  how the positions are sampled: 65.2% over BC's land polygon (20,000 pdist calls, and 65.0% from
  the analytic expectation over 2e5 points), 54.5% over x in [2e5, 1.9e6], and 49.7% over the
  EPSG:3005 area-of-use bbox. The point it makes, that a random position does not always
  reproduce, holds either way. The pinned position (878010, 1261000) to (878010.03, 1261000) does
  return 0 from pdist.
- "the serial path no longer holds both the pdist object and its matrix" is true. At d3918f1,
  `node_dist` (R/lines_to_lsn.R:349) stayed bound for the rest of the function, with no rm(),
  next to `dist_matrix`. HEAD has only `dist_matrix`.
- "replaces all five pdist() calls": `git grep 'pdist(' d3918f1 -- R` finds exactly 5 (3 in
  lines_to_lsn.R, 1 in pdist_node_coords.R, 1 in pdist_rid_confl.R). None is left in R/,
  DESCRIPTION, NAMESPACE, vignettes or man.
- NEWS bullet 1 and commit 9d759a9 ("fail on 1.1.2: ... two unsnapped nodes and two downstream
  divergences, and its edge relationships are wrong"): with d3918f1 under load_all and the 3-line
  chain at (878000, 1261000), node_errors has 4 rows on pointids 2 and 3 (Unsnapped Node x2,
  Downstream Divergence x2). nodecat is Confluence x2, Outlet, Source. relationships is
  1->2, 1->3, 2->2, 2->3. Confirmed.
- NEWS bullet 3 and commit 6ebcc90, traced in the code: a one-row to_xy chunk drops to a vector,
  so `rownames(to_xy)` is NULL and the confl.list element has no name. After `.combine = 'c'` its
  name is "", and `as.integer(names(to_rids))` gives NA for fromedge (R/lines_to_lsn.R:670).
  Confirmed.
- Test comments: 701 nodes give chunk.no = 2, split 351 + 350. In the parallel test the 3 cm
  line's nodes are global rows 650/651, which are local rows 299/300 of chunk 2. In the combiner
  test, rows 351/352 straddle the boundary and rows 600/601 are both in chunk 2. All correct.

## Code, reviewed again

No new defects. Checked against the applicable checklist items:
- `tools:::.check_packages_used_in_tests()` on a HEAD copy returns nothing (pass). The test uses
  sf, withr and utils, all declared.
- The tests reach internals (dist_xy, combine_node_chunks, split_matrix, pdist_node_coords)
  unqualified. That is fine under R CMD check, because testthat runs tests in a child of the
  namespace.
- Empty geometries are rejected at R/lines_to_lsn.R:113, so pdist's NaN-skip behaviour, which
  dist_xy does not reproduce, cannot be reached.
- dist_xy: `block_size` floors to 1 when NROW(b) > 5e6. Its orientation (rows a, columns b)
  matches `as.matrix(pdist)`. `out` is local with one reference, so `out[i, ] <-` writes in place.
- The only skip is skip_on_cran on the parallel test, which is accepted. The serial and combiner
  tests always run.
