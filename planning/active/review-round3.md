# Review round 3: SSNbler fix-pdist-precision-parallel-unsnapped (d3918f1..HEAD)

Verdict: the code is clean. Four documentation claims, in NEWS.md, R/dist_xy.R and two commit messages, still come from the model that produced the round 1 and round 2 errors.

## The mechanism behind the wrong figures

All of the wrong figures share one assumption: pdist's error was treated as a fixed tolerance, one number `s` for the data, below which a distance reads as 0. That is not what pdist does. pdist 1.2.1's R wrapper calls `as.single()` and then `.C("Rpdist")`, so the C code works in `float`. Each coordinate is rounded on its own to the nearest float, and the two rounded values are then subtracted exactly. A distance is therefore 0 **exactly when both x values round to the same float and both y values round to the same float**. I checked this against pdist on 3,000 random BC pairs (`f32()` via `writeBin(size = 4)`), and it agreed on every pair, including all 1,522 zeros.

That rule depends on four things, and the fixed-tolerance model drops each of them in turn:

| dimension the real rule has | what the fixed-tolerance model assumed | instances it produced |
|---|---|---|
| spacing depends on the coordinate's magnitude (binade) | one spacing for the dataset | "~6 cm" (round 2), "~1 cm at 2e5" (round 2), **"0.5 m at UTM northings"** (still present) |
| spacing is set per axis, and x and y can sit in different binades | one spacing for both axes | "up to the spacing apart" (fixed to 1.4x), **"up to 1.4 times it on a diagonal"** (still present) |
| a zero is a rounding coincidence that depends on position, with probability (1-\|dx\|/sx)(1-\|dy\|/sy) | a threshold: closer than s means 0 | **"returns 0 for points closer than about the spacing"**, **"about that close"**, **"A line ... then read as"** (still present) |
| (other domains) a value that varies with input size or position | the value seen in the one configuration examined | "500-node chunk" (a cap), "~63%" (a range), **"flags landed on the wrong nodes"** (only true after the first chunk) |

Stated generally, a quantity that is a function was quoted as the constant it takes at the one configuration that was looked at: the test's pinned coordinate (878000, 1261000), an east-west segment, and one network size.

## Findings

- **[fragile] NEWS.md:5**: "it returns 0 for points closer than about the spacing of floats". This is a threshold, but the real behaviour is a probability. I measured how often a 6 cm east-west pair reads 0 in the [2^19, 2^20) band, where the spacing is 6.25 cm: **4.0%** (1e5 uniform x positions). A 3 cm pair reads 0 at 4.1%, 52.1% and 76.1% in the 2^18, 2^19 and 2^20 bands. The phrase is right only as an upper bound ("can return 0 only for points closer than the spacing on each axis").
- **[fragile] NEWS.md:5**: "(up to 1.4 times it on a diagonal)". This needs x and y to have the same spacing. The true largest zero distance is sqrt(sx^2 + sy^2). At the test's own coordinates sx = 0.0625 and sy = 0.125. I measured with pdist: the pair (878000-0.0312, 1261000-0.0624) and (878000+0.0312, 1261000+0.0624) is **0.1395 m** apart, and pdist returns 0. That is **2.23x** the x spacing and 1.12x the y spacing. "1.4x" holds only as a bound on the *larger* axis spacing, which the sentence does not say.
- **[fragile] NEWS.md:5**: "0.5 m at UTM northings". This is true only for northings in [4,194,304, 8,388,608) m. I transformed points in sf (EPSG:4326 to 32610, lon -123): 37.8 N gives 4,183,625 m and spacing **0.25**; 37.9 N gives 4,194,720 m and spacing 0.5; 75.7 N gives 8,401,711 m and spacing **1.0**. It covers BC (about 5.35M to 6.65M m) but not UTM in general. That matters because this NEWS entry is written for upstream pet221/SSNbler, whose US users south of about 38 N get 0.25 m.
- **[fragile] NEWS.md:5**: "A line a few cm long then read as two unsnapped nodes and two downstream divergences". "Then" makes it certain, but it happens only when the line's ends round together. I measured a 3 cm line reading 0 at **56.7%** of positions uniform over the BC Albers bbox (east-west segment; 51.8% for a random direction). The symptom itself is confirmed: on d3918f1, installed to a temp library, the pinned 3-line chain gives `Downstream Divergence 2, Unsnapped Node 2` and relationships 1->2, 1->3, 2->2, 2->3. The fix gives no errors and 1->2, 2->3. "could read" would be accurate.
- **[fragile] R/dist_xy.R:3-6**: has the same two claims, "0.5 at UTM northings" and "returns 0 for points about that close". These are wrong for the same reasons and measurements as the NEWS findings above.
- **[fragile] commit affbd8d message**: has the same three claims, "0.5 at UTM northings", "pdist returns 0 for points about that close" and "(up to 1.4 times it on a diagonal)". `0.015625 at 2e5` is correct (2^(17-23)). "its C code converts to float" is slightly off: the conversion is the R wrapper's `as.single()`, and the C code is float throughout. It does no harm. The branch is not pushed (`git branch -r --contains HEAD` is empty, ahead 4 of upstream/develop), so the message can still be reworded.
- **[fragile, low] NEWS.md:6 and commit ff8d21c**: "the Unsnapped Node flags landed on the wrong nodes" / "flagged the wrong nodes". This is true only for chunks after the first: chunk 1's local rows are global rows, so its flags were correct, and only a pair split across a boundary was missed. I reproduced it on d3918f1 (`R_LIBS` set to the temp library so the workers load the base package) with the test's 701-node fixture: base returns `249 250` where the answer is 351, 352, 600, 601. Rows 351 and 352 are missed because the pair is split across the boundary, and 600/601 come back mislabelled as 249/250.

Suggested wording for the NEWS sentence, which also covers the dist_xy comment and affbd8d: "pdist::pdist() rounds coordinates to single precision before subtracting, so two points read as 0 apart whenever both their x and both their y coordinates round to the same float. The float spacing grows with magnitude and is set separately for x and y: 0.0625 m from 524,288 to 1,048,576 m, 0.125 m to 2,097,152 m, 0.5 m from 4,194,304 to 8,388,608 m (UTM northings from about 38 to 75 N). A line a few cm long could then read as ..."

## Claims checked and found to hold (with how)

- NEWS "0.0625 m from 524,288 to 1,048,576 m, 0.125 m to 2,097,152 m": computed as 2^(e-23), and matches pdist's quantisation.
- NEWS item 2, "chunk of up to 500 nodes": `max.rows` is capped at 500 and the chunk size is `ceiling(n/ceiling(n/max.rows))`. Over all n up to 3e6 the largest chunk is 500.
- NEWS item 2, the remaining text (duplicates within a chunk only, chunk-local rows, pair split across chunks missed): reproduced on base (above).
- NEWS item 3 and commit 8505fb5, "fromedge becomes NA": on base, `split_matrix(to, 3)` of 7 rows gives chunks of 3, 3 and 1. The one-row chunk is a vector, its name comes back as "", and `as.integer()` turns it into NA. Through lines_to_lsn a one-row last chunk is only reachable at n = 1 (the known pre-existing failure) or at ≥ 249,501 edges: 31,929 sizes up to 3e6, the first being 249,501, then 250,001 and every 500 after. The claim is accurate, and no frequency was claimed.
- Commit affbd8d, "all five pdist() calls": `git grep "pdist(" d3918f1 -- R` finds exactly 5. No pdist use remains in R, tests or DESCRIPTION; only comments mention it.
- Commit 96303516, "They fail on 1.1.2": the v1.1.2 tag and d3918f1 are identical in the six affected R files (`git diff --stat` is empty). The 3 cm symptom was measured on base, as above.
- Test comment "half to two thirds of random positions in BC Albers": measured 56.7% for east-west segments uniform over the bbox and 51.8% for random directions. The pinned 878010 vs 878010.03 gives pdist 0, which confirms "pdist reads this 3 cm as 0".
- Test comments "701 nodes ... chunks of 351 and 350", "351/352 across the boundary, 600/601 within the second", "rows 299/300 of the second": `ceiling(701/2) = 351`, and node order follows `unique(st_coordinates(...))`, so 650 - 351 = 299 and 651 - 351 = 300. "lines_to_lsn() deduplicates nodes": it rounds to ndec and drops duplicates, so identical coordinates cannot both survive.
- Test comment "offsets exact in binary": 9·2^-14 + 16·2^-14 = 25·2^-14, whose square root is exactly 5·2^-7, and every coordinate plus offset can be represented in double up to 2e6.
- The test file passes on a temp copy of HEAD, including the parallel test with NOT_CRAN=true: 31 expectations, 0 failures.

## Code, reviewed again

Clean. I checked:

- dist_xy() on a vector, a data.frame, zero rows and one row.
- The lazy `block_size` default: it is evaluated after b is coerced, and never when nrow(b) = 0.
- combine_node_chunks() with no zeros (0x2 matrices), a chunk with a single zero, a single chunk, and integer offsets.
- That the serial and combined results agree in type and names (none on either side).
- `split_matrix(drop = FALSE)` on the node path, where node_coords is a data.frame and is unchanged, and on the rid path, where it is a matrix and is fixed.

Unsnapped ends inside snap_tolerance behave the same on base and on the fix: offsets of 0.0005, 0.007 and 0.04 m at tolerance 0.001 and 0.1 gave no errors on either, because ndec deduplication absorbs them. So the change in precision does not surface new true errors that 1.1.2 hid.

Probes are in scratchpad/r3/ (probe1 to probe5.R, base install in r3/lib). Nothing in /Users/airvine/Projects/repo/SSNbler was modified.
