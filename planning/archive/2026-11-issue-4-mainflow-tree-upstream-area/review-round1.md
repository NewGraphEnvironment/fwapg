# Code-check round 1: branch `4-upstream-area-on-the-main-flow-tree-so-s` at 30f2846 (base 28fb2ac)

Reading round, 2026-11-20 (15:51 to 16:15 UTC). No database was touched. Checked offline only: `bash -n` on both
shell scripts, `parse()` of `ssnbler_check.R`, the new shell lines under `/bin/bash` 3.2.57 with `set -euo pipefail`,
a scan of the added lines for private references (none), and the two issue numbers the documents add (#4, #52:
both resolve to this work). Where a finding says "needs a probe", the query is given and was not run.

## Checklist read

- `code-check-infra.md`: in full.
- `code-check-python.md`: in full (no Python in the diff).
- `code-check.md`: the prose of all 14 mechanisms (table rows skipped); of the standalone rules, "Documentation
  Staleness", "An ordered dispatch makes severity ordering load-bearing, and nothing enforces it", "Test the
  cold/create path of idempotent code, not just the warm no-op", "An assertion that matches an interpolated value
  cannot see the claim around it" (rule text, not its evidence), "Process Visibility", "Credentials". 18 headings not
  read (the other standalone rules, the rest of Security, Spreadsheets and PDFs).
- `code-check-shell.md`: "psql does not interpolate `:'var'` inside a dollar-quoted string, and `\quit N` exits 0",
  "A value validated with one numeric grammar and consumed with another", "`if ! cmd; then rc=$?` captures the
  negation, not the command", "A second `trap … EXIT` replaces the first", "`grep -c` prints the count AND exits 1
  when it is zero", "`a && b || c` runs `c` when any step before the `||` fails", "`for x in $(cmd | grep … || true)`
  hides a failing `cmd`", "Quoting". 64 not read.
- `code-check-r.md`: "Postgres row order is never fixed unless the query fixes it, so a pick, a float sum and a
  presence check can each depend on it", "A database driver's value is not a base R type — and it fails twice",
  "`$` on a list partial-matches, so a longer sibling key answers for a missing one", "`tryCatch()` nests its
  handlers, so a `stop()` in one is caught by a later one", "`tryCatch(warning = )` DISCARDS the value the expression
  produced" (first half), "A range total taken as the difference of two large running totals loses the small ranges".
  120 not read.
- `code-check-spatial.md`: "FWA `upstream_route_measure` misses the next segment's start", "FWA main flow is not edge
  type 1000 alone", "A Freshwater Atlas main stem's downstream end lies on the receiving river's centreline, not at
  the confluence", "A GDAL failure partway through `sf::st_read()` returns the rows read so far, with only a
  warning", "Ask the file about its field names, not R". 89 not read.

## Findings

Ordered by how much I would want each settled before the PR. The first three are certain from reading; the rest say
what a probe has to show.

- **[severity: bug]** `extras/mainflow_tree/sql/qa.sql:255-256` and `:285-287` — the basin test and the side-channel
  test can pass with a member missing. Both are written `count(*) = N AND coalesce(bool_and(<cond>), false)`.
  `count(*) = N` cannot fail: `mouth` and `measured` are built from a `VALUES` list with scalar subqueries, so they
  always hold 2 and 4 rows. `bool_and()` skips NULL inputs, and `<cond>` is NULL whenever a scalar subquery finds
  nothing (`abs(NULL - x) <= …`; `true AND NULL AND NULL`). So the `coalesce` catches only the case where every row
  is NULL. If the Nechako's code, one tributary's code or one side channel's key stops matching (an FWA re-release
  that recodes a stream, which is the README's own reason these keys go stale), the test prints `t` on the members
  that are left. Two of the NULL routes are caught elsewhere (a side channel with no tree segment below its entry
  fails "four Skeena side channels are kept…"; a NULL area fails the positive-area test); "no polygon under the
  tributary's or basin's code" is caught nowhere. `count(*) FILTER (WHERE <cond>) = N`, the form tests 1 to 3 already
  use, counts a NULL as a miss. The single-row test at `:292-300` is not affected.
  - **Rule:** code-check.md "A guard that fails toward pass"

- **[severity: bug]** `extras/mainflow_tree/sql/qa_area.sql:156-160` (against its header at `:24` and
  `mainflow_tree_area.sql:195-202`, `:228-244`) — the `side polygon` marker covers `method = 'pair_side'` only, but
  rules 3 and 4 can also give a polygon to a reattached or followed segment. `area_reach` holds every code pair on
  the tree, main flow first only *within* a pair, so the reach "at the greatest local code at or below" a polygon's
  can be one that exists on a side channel alone. Such a polygon is routed down the side channel, not past the
  main-river segments its codes put it above, which is exactly what kind 7 exists to mark; it gets no marker, so
  those main-river segments read "nothing routed differently" and differ. The prototype counted 56 polygons,
  158,932 ha, placed this way (`findings.md`, "own stream, a lower local code (reattached)"); the final build's
  count is not recorded. Two consequences worth separating:
  1. the comparison: a candidate cause for some of the 17 unexplained segments, and the header's definition ("a
     polygon given to a reattached or followed segment") is wider than the predicate;
  2. the build: polygons averaging about 2,800 ha in the prototype land on side channels whose point is to carry
     only what enters them. Whether rule 3 and 4 should take main-flow reaches first is the owner's call; no test
     bounds the area that `lower` and `ancestor` put on non-main-flow segments.
  Needs a probe:
  `SELECT p.method, t.source, count(*), sum(p.area_ha) FROM fwapg.mainflow_tree_area_polygons p JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t USING (linear_feature_id) GROUP BY 1, 2 ORDER BY 1, 2;`
  A lesser point in the same place: the two counts compared per kind are counts, not sets, so one marker the tree
  has and the codes do not cancels one the other way round. That fails toward "unexplained", not toward hiding, but
  the README's "a main-flow segment whose counts are equal has to agree with the lookup" (`README.md:79-80`) is
  stronger than what is tested.
  - **Rule:** code-check.md "A proxy is not the property"

- **[severity: bug]** `research/fwa_mainflow_tree.md:56`, `extras/mainflow_tree/sql/mainflow_tree_area.sql:116-118`,
  `sql/qa_area.sql:26-28` — "`FWA_Upstream` has guards that leave them out, so the lookup counts them nowhere" is
  not what the function says, and not what `qa_area.sql` itself models 150 lines further down. In
  `db/schema.sql:3215-3253` the tributary arm and the mouth-reach arm have the guards; the same-stream arm
  (`wscode_ltree_b = wscode_ltree_a AND localcode_ltree_b >= localcode_ltree_a`) has none, and the tributary arm
  still admits a bad local code that is under the *ancestor's* code. `qa_area.sql:175-193` encodes exactly that
  ("counts on an ancestor only where it is under that ancestor … on its own stream it does not count for the mouth
  reach"). So the research file, the build's comment and the comparison's header state "nowhere" while the code
  beside them says "in some places"; the 16,398-segment `bad code` class is consistent with either. Say what the
  function does: leaves them out at the mouth reach and for ancestors the local code is not under.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

- **[severity: fragile]** `extras/mainflow_tree/sql/mainflow_tree_area.sql:195-202` — the fix for a code pair that
  reappears further up a line landed in rule 1 only. `area_pair_top` takes the lowest run that holds the pair, "or
  it would pull its polygon up there"; `area_reach`, which rules 2 to 4 read, takes `drm DESC` over every appearance
  of the pair on the line, so for one of the 77 reappearing pairs it is the *upper* appearance. A `lower` or
  `ancestor` polygon whose target reach is one of those pairs is placed above segments its codes do not put it
  above. (`qa_reach` in `qa_area.sql:69-74` has the same shape; there it only adds a spurious `other place` marker
  counted equally on both sides, so it is harmless.) Needs a probe: of the `lower` and `ancestor` polygons, how many
  sit on a segment whose (watershed code, local code) is in more than one run of `area_pair_top`'s `numbered` CTE.
  Likely few or none; the hazard is the one the file already names.
  - **Rule:** code-check.md "A fix lands in one of two callers that share a harness"

- **[severity: fragile]** `extras/mainflow_tree/ssnbler_check.R:112`, `:139-142` — the one check that can tell a
  wrong area runs only on edges whose `linear_feature_id` is one of three literals, and "none found" looks the same
  as "checked and fine" in the exit status. (a) On any subset holding none of them, which is everything outside the
  lower Skeena, `area: ok` means only "every area is positive"; the file's own comment says those limits hold for
  any positive areas. The line does print `side channels: 0`, but the run exits 0. (b) 123041439 (said to be
  360216952's mouth) has not been held by any recorded run: KLUM held the other two, the tributary basin none
  (`findings.md`, Phase 5). A mistyped id, or a streams file with no `linear_feature_id` column
  (`NULL %in% x` is `logical(0)`), disables the check with no message. Needs a probe:
  `SELECT linear_feature_id, blue_line_key, downstream_route_measure FROM whse_basemapping.fwa_stream_networks_sp WHERE linear_feature_id IN (123041439, 87082084, 87078272);`
  and one run on a subset that holds 123041439. Where the wscode argument is `400` with no group, or the group is
  KLUM or the one holding 360216952, zero held edges could be a failure, not a pass.
  - **Rule:** code-check.md "A guard that fails toward pass"

- **[severity: fragile]** `extras/mainflow_tree/sql/mainflow_tree_area.sql:377-400` with `sql/qa.sql:134-139` — a
  segment that gives a length share can be left with a float residue as its whole area, and the positive-area test
  passes a residue. The zero segments in a polygon take `area * len / total`, where `total` is their own length plus
  the length of area-carrying tree segments *whose midpoint is in the polygon*. Where there is none of the latter
  (the polygon was given to a segment that does not lie in it: `lower`, `ancestor`, a bad-code polygon sent to its
  stream's mouth, a run top beyond the polygon), the zero segments take all of it and the owner's
  `local_area_ha - sum(share)` is 0 give or take rounding, of either sign. If the owner has nothing else and nothing
  above it, its area and that of every segment below it to the next inflow is that residue: `<= 0` fails test 1
  (loud), `1e-13` passes it. The current build prints `t`, so there is no non-positive one; a residue cannot be
  ruled out by reading. Needs a probe:
  `SELECT count(*), min(upstream_area_ha) FROM fwapg.mainflow_tree_area WHERE upstream_area_ha < 0.01;` and
  `SELECT count(*) FROM fwapg.mainflow_tree_area WHERE shared_area_ha < 0 AND local_area_ha < 0.01;`
  A floor in the test (the smallest polygon is far above a residue) would make "positive" mean an area.
  - **Rule:** code-check.md "A proxy is not the property"

- **[severity: fragile]** `extras/mainflow_tree/README.md:185-186`, `:189`, `:192`, `:328-329`;
  `research/fwa_mainflow_tree.md:60`; `sql/qa.sql:236` — figures the documents give for the 2026-11 build that
  `findings.md` either does not hold or holds only for the prototype, which ran before rule 1 was restated, before
  the 6010 fix and before bad-code polygons were sent to the mouth (assigned area moved 110,142,095 to 110,143,670
  ha between the two).
  | document | figure | `findings.md` |
  |---|---|---|
  | README `:189` | Fraser at its mouth 23,198,692 ha | 23,198,766 (prototype, twice); no later figure |
  | README `:185-186` | 360222215 and 360222216 read 228,962 to 229,063 ha | 360222215 reads 228,942.8 (prototype). 228,962 is what the final rule 2 would give (the 19.3 ha polygon goes to the lower blue line key), so the README looks re-measured and the record is what is missing |
  | README `:328-329`, research `:60` | 184,742 ha above the 384 outlets inside BC, largest 50,535 | 184,525 + 217 = 184,742, both prototype figures; not re-measured in "The build as it stands" |
  | README `:189`, `qa.sql:236` | Skeena 5,440,479, Nechako 4,725,598; "0.003% and 0.004%" | equal to the prototype's; plausible, not recorded for the final build |
  | README `:192` | median share 45 ha, largest 37,633 ha | not in `findings.md` |
  Needs a probe for the 184,742 (sum of `upstream_area_ha` over `downstream_id IS NULL` joined to the dead ends and
  cut-offs of `fwapg.mainflow_tree_qa`), and one line in `findings.md` for each of the others with what produced it.
  - **Rule:** code-check.md "The probe is broken before the world is" ; code-check.md "Written data outlives the fix"

- **[severity: fragile]** `extras/mainflow_tree/sql/mainflow_tree_area.sql:119-125`, `:280-285`, `:320-325` — the
  area is not reproducible to the bit between two builds of the same inputs. `area_poly` is filled by a
  `CREATE TABLE AS` over `fwa_watersheds_poly` with no order (a parallel or synchronized scan may return rows in
  another order each run), `sum(area_ha) … GROUP BY linear_feature_id` then adds each segment's polygons in that
  order, and the level sums add children in whatever order the plan gives. The tests compare at 1e-9 relative, so
  they are unaffected. What is affected: the plan's Phase 7 step "the column's checksum compared with the one
  SSNbler ran on" will differ after any rebuild with nothing changed, and so will a byte compare of two
  `fwa_stream_networks_mainflow_tree.csv.gz` exports. Compare on `linear_feature_id` under a tolerance, or order
  the three sums. Needs a probe to see it (build twice, `md5(string_agg(upstream_area_ha::text, ',' ORDER BY linear_feature_id))`).
  - **Rule:** code-check-r.md "Postgres row order is never fixed unless the query fixes it, so a pick, a float sum and a presence check can each depend on it"

- **[severity: fragile]** `extras/mainflow_tree/sql/mainflow_tree_area.sql:424-428` with `sql/qa.sql:210-216` and
  `README.md:333-334` — `no stream` is assigned by elimination (`WHEN w.wscode_ltree IS NOT NULL`), not by the
  property its comment and the README state ("its watershed code, and every ancestor of it, is on no tree
  segment"). Rule 3 and 4 leave a polygon unplaced on a narrower condition: no reach at or below its local code on
  its own code, and no ancestor reach strictly below the branch. So the test's `class IS NULL` arm can fire only
  for a NULL watershed code, and a polygon whose stream *is* in the tree but that a regression left unplaced would
  be labelled `no stream`; only the ceiling of 53,209 would notice, and only if the count rose. Phase 1 measured
  the property for the first rule's 53,225; it is not measured for the 53,209. Needs a probe: unassigned polygons
  whose watershed code or an ancestor of it is the watershed code of a tree segment (expected 0).
  - **Rule:** code-check.md "A proxy is not the property"

- **[severity: fragile]** `extras/mainflow_tree/ssnbler_check.sh:187-191` — with `SSNBLER_AREA=1`, exit 0 is not
  tied to an `area: ok` line, although exit 0 and 1 are tied to the `node errors:` line and exit 6 to
  `area: failed` ("any other status, or no result line, is a failure (5)"). R exiting 0 with no `area:` line would
  be reported as exit 0 with `area: not run` in `runs.log`. I found no route to it in the R file as written (the
  only `quit(status = 0)` is behind the environment test, and everything after it is inside the `tryCatch`), so
  this is the contract being one-sided, not a live failure: `[ "$SSNBLER_AREA" = 0 ] || grep -q '^area: ok' "$log"`
  on the first arm closes it.
  - **Rule:** code-check.md "A wrapper's exit is not the work"

- **[severity: fragile]** `extras/mainflow_tree/sql/qa.sql:1-2`, `sql/qa_area.sql:3` — two "run after" headers are
  short of what the files now read. `qa.sql` says "Run after qa_topology.sql" and now also reads the tables of
  `mainflow_tree_area.sql` and `qa_area.sql`; `qa_area.sql` says "Run after mainflow_tree_area.sql" and also reads
  `fwapg.mainflow_tree_qa` (from `qa_topology.sql`), `fwa_streams_watersheds_lut` and
  `fwa_watersheds_upstream_area`. Run by the header after an area rebuild alone, `qa.sql` reads the previous
  build's `fwapg.mainflow_tree_area_qa` and `_qa_counts` and its last three tests answer about that build.
  `mainflow_tree.sh` runs them in the right order.
  - **Rule:** code-check.md "Documentation Staleness"

- **[severity: fragile]** `extras/mainflow_tree/sql/mainflow_tree_area.sql:437` — `ALTER TABLE … ADD COLUMN IF NOT
  EXISTS` takes its ACCESS EXCLUSIVE lock before it looks, so on a tree that already has the column (every run
  after this branch) it still waits behind any session reading the tree, with no `lock_timeout`, after the five
  minutes of build are done. Reading `information_schema.columns` first, or a `lock_timeout` for the statement,
  turns a silent wait into an error. Low: in the full job the table was dropped and recreated minutes earlier under
  the same lock.
  - **Rule:** code-check-infra.md "Set `statement_timeout` + `lock_timeout` on long DB ops"

## Asked, with no finding

What the brief asked to have tested, where reading found nothing wrong.

- **`area_pair_top` runs.** A main-flow segment whose pair is a polygon's pair always lands in a run with
  `has_pair` (its `grp` is its own local code), so `pair_side` can only be a non-main-flow segment. The 6010
  connectors are left out of the window, so they do not break a run. `DISTINCT ON … ORDER BY …, bottom,
  blue_line_key` ends on a unique key. Every other pick in the two new SQL files ends on a unique key too
  (`area_reach`, `qa_reach`, the mouth pick, both midpoint laterals, the step-5 lateral).
- **The gap steps.** One row per segment (unique `(up_x, up_y)`), the lateral runs only for rows with no node
  step, step 0 before the path steps, the 1 mm side of the junction is the right one (a junction on a node takes
  the segment below it). A step that points upstream makes a cycle, and the `depth IS NULL` check raises on it. A
  segment shorter than the 1 cm cell would fail the unique index as a "split": none exists today (0 splits).
- **The level loop.** Depth is well defined (one parent each), children of depth d are all at d + 1, the loop is
  empty for a tree of outlets only, and an empty table fails loudly on the NULL bound. No plpgsql variable shadows
  a column.
- **Step 7.** A share cannot be taken twice: one row per zero segment (primary key), the owner's subtraction is one
  grouped sum, and a segment cannot be both receiver and giver (receivers are fixed at area 0 before sharing). The
  shares out of one polygon never exceed it. A polygon given to no segment adds its shares to the tree with nothing
  subtracted; `shared_ha` records it and the outlets test counts it (667 ha). The owner-at-a-residue case is the
  finding above.
- **The marker encoding.** `power(10::numeric, …)` is exact for an integer exponent and the slot extraction is safe
  while the slot below holds fewer than 500,000 (the division can round to an integer when the quotient is long);
  the largest count is far under that. The comment's "far fewer than a million" should read half a million. The
  code-side sums match `FWA_Upstream` arm by arm for valid codes, and for bad codes except one corner (a bad local
  code *equal* to an ancestor's code is under that ancestor's mouth reach by the function and not counted by
  `pos > localcode`), which can only mislabel.
- **The class `CASE`.** Every arm is an explanation and NULL is the verdict, so order only decides which label a
  segment with two reasons gets; the three lookup-match arms that shadow routing have ceilings in `qa.sql`.
  `reattached`/`followed` and the routing strings have none, by design: a wrong area on a segment with any marker
  difference is "explained", so the comparison tests the build on the 4.29 million routed-alike segments and no
  further.
- **The recompute `UPDATE`.** Same definition as `extras/lookups/sql/fwa_watersheds_upstream_area.sql`, independent
  of the tree; relabels only where the tree equals it; more than 5,000 leftovers stay NULL and fail the test.
- **`qa.sql`, can each fail, and what prints.** Every new statement is one aggregate or a `SELECT` with no `FROM`,
  so each prints one line; a NULL result prints `name|` and fails; a missing table stops psql and `set -e` stops
  the script. On empty tables every new test prints `f` or `name|` except "at most 97 steps … and 869 segments",
  which is ceilings only and prints `t` (the others stop the run). Tests that read only the build's own tables:
  the outlets sum (both sides), the additive test's `local_area_ha`, the ceilings. Tests anchored outside it: the
  additive test's inflows (geometry), the basin, side-channel and tributary-mouth tests (polygons under a code),
  and the three lookup tests.
- **`ssnbler_check.sh` arguments and statuses.** `SSNBLER_AREA` unset, empty, 0 and 1 behave; a trailing newline is
  refused. `[ … = 1 ] && columns=…` does not trip `set -e` at top level (run under `/bin/bash` 3.2.57: the default
  path reaches the next line). R's 6 becomes 6 only with an `area: failed` line and no kill; a kill keeps 3 or 4;
  an NA share or a missing column inside the step ends as `area: failed` (6), not a crash. A topology failure skips
  the step and `runs.log` reads `area: not run`.
- **`mainflow_tree.sh`, order and what a failed run leaves.** The order is right for every table each step reads.
  Nothing is in a transaction, so a failure inside `mainflow_tree_area.sql` leaves `fwapg.mainflow_tree_area_polygons`
  and `fwapg.mainflow_tree_area` new (possibly before sharing) beside the previous build's `_shares`, `_unassigned`,
  `_qa` and `_qa_counts`, with the tree's column NULL (full job) or still the previous build's (the file run
  alone). A QA failure leaves the database fully rebuilt, `data/qa_area.csv` rewritten and the old `.csv.gz` in
  place. Both follow how the job already treated the tree and `qa_topology.csv`; no marker says which state the
  tables are in, and test 1's equality arm is what would show the standalone case.
- **The export's new column.** `SELECT *` now writes five columns. Nothing in this repo loads the file, and a
  search of the organisation's default branches found no code that does.
- **Public-repo text.** No host, port, credential or private-repo name in the added lines.

## Not settled by reading

- Whether any of the 17 unexplained segments is the `lower`-on-a-side-channel case or a cancelling pair of
  same-kind markers (second finding).
- The final build's counts for every "needs a probe" above.
- SSNbler's `afv_edges`, `sites_to_lsn` and `afv_sites` were not read; the call signatures match what `findings.md`
  records and the KLUM run.
