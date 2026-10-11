Fixes #8.

Three changes, one commit each, plus a commit of tests that fail on 1.1.2. The PR targets `develop`, which is 1.1.2.9000 and has the dev NEWS header. Please say if you would rather it went to `main`; CI runs on PRs to `main`.

## 1. Node distances in double precision

`pdist::pdist()` rounds coordinates to single precision before subtracting (`as.single()` in `R/pdist.R`, `float` in `src/pdist.c`). Two points therefore read as 0 apart whenever their x and their y each round to the same float. Float spacing grows with magnitude (0.0625 at 10⁶), so at projected coordinates points several cm apart can read as 0. A line a few cm long can then show up as two Unsnapped Nodes and two Downstream Divergences, and its edges are joined wrongly in `relationships.csv`. Shifting to a local origin only narrows the problem to the extent of the data.

The new internal `dist_xy()` computes from coordinate differences in double precision. It replaces all five `pdist()` calls (`rid_confl` and the topology check, on both the serial and parallel paths), and pdist is dropped from Imports. It fills the matrix in row blocks, so the serial path no longer holds the pdist object and its matrix at the same time.

## 2. Duplicate to nodes across chunks on the parallel path

`pdist_node_coords()` counted duplicate to nodes within its own chunk and returned `unsnapped_tonodes` as row numbers within that chunk. `get_pdist_nodes()` then concatenated them with no offset. As a result, flags from every chunk after the first landed on the wrong nodes, and a pair split between two chunks was missed. Each chunk now returns its zero-distance (node, edge) pairs, and the new `combine_node_chunks()` offsets them by the real chunk sizes and counts duplicates over all chunks. This matches the serial computation on the whole matrix.

Once distances are exact, this mechanism cannot fire through `lines_to_lsn()`. Nodes are deduplicated before the check, so no to-end is at distance exactly 0 from two of them. It only fired because of (1). The test therefore calls the chunk functions directly, with duplicate rows inside one chunk and across a chunk boundary. You may prefer to remove the mechanism rather than keep it. The fixed version is here in case it has a purpose I have missed.

## 3. `split_matrix()` keeps a one-row chunk a matrix

`mat[i:j, ]` turns a one-row chunk into a vector. In `get_pdist_rid()` that loses the chunk's row name, which is the rid, so that edge's `fromedge` comes out NA. Through `lines_to_lsn()` this only happens at certain network sizes from 249,501 edges.

## Tests

`tests/testthat/test-topology_precision.R`:

- `dist_xy()` against distances that are exact in binary, from 10⁰ to 10⁶, plus shapes and block sizes
- `split_matrix()` chunk shapes
- the parallel combiner against the serial formula
- a 3 cm line at BC Albers coordinates: no node errors, and relationships 1→2, 2→3
- the parallel path against the serial path on 700 lines (`skip_on_cran()`, 2 cores)

Each fix was reverted on its own, and each revert makes at least one test fail. `R CMD check --as-cran`: 0 errors, 0 warnings, 1 NOTE (the `.9000` version). 188 tests pass.

## Checked on real data

These checks used BC Freshwater Atlas networks (EPSG:3005) with `snap_tolerance = 0.001`.

- **Results:**
  - Two watershed groups (21,655 and 24,732 lines, serial) went from 4 false errors each to 0.
  - A whole basin (261,764 lines, parallel) went from 6 to 0, with 1 outlet. The parallel path is slower, though: 54 min against 35, since `dist_xy()` is R where pdist is C, while its peak memory fell from 20 to 11 GB.
  - A 52,293-line basin that was already clean (parallel) gives `relationships.csv`, `noderelationships.csv` and `nodexy.csv` byte-identical to 1.1.2.
  - So do the package's own `MF_streams` (EPSG:5070) on both paths.
- **Peak memory on the serial path** went from 28 to 18 GB and from 37 to 24 GB on the two groups.

## Not changed, for your judgement

- **End points.** `st_line_sample(sample = 1)` can land one ulp (about 1e-10 m) off a line's last vertex on long lines. With exact distances, that end reads as 0 < d ≤ tolerance. It is harmless while both points round into the same `ndec` bin, because the nodes merge and the Unsnapped error at a merged node is dropped. I could not construct a case where the drift crosses a bin edge. Taking ends from `st_coordinates()` would remove the question.
- **Rounding bins.** Node rounding uses `ndec = get_decimals(snap_tolerance) - 1`, so `snap_tolerance = 0`, the default, rounds to 10 m.
- **Serial `rid_confl`.** It uses `apply(..., 2, which(...))` without `simplify = FALSE`, so in principle it can return a matrix rather than a list.
- **One-line networks.** `lines_to_lsn()` fails at the `left_join` that builds `noderelationships`.
