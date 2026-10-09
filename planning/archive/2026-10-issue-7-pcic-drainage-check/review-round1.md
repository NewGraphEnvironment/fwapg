# Code check, round 1: fwapg#7 drainage check (staged diff)

Scope: `git diff --cached`, with qa_drainage.sql (new), qa.sql, pcic_crosswalk.sh, README.md and planning/active/*.md read in full. I checked the diff against the relevant checklist sections (Docker/Postgres, psql, the Mechanisms section, documentation staleness) and ran queries against the local DB without writing to it.

## Findings

- **[severity: fragile]** extras/pcic_crosswalk/sql/qa.sql:126-130 (with qa_drainage.sql:115-119, 127). The new ceiling test can pass without checking anything. Its only guard against an empty result is `count(*) FILTER (WHERE main_stem) > 0`, which shows that rows exist, not that ratios were computed for them. When `density_ratio` or `runoff_ratio` is NULL, neither CASE arm matches, so `flag` is NULL. That outlet then counts as neither `small` nor `big`, and the qa_drainage.sql report labels it `ok`. A NULL ratio comes from:
  - a placed segment with no row in `fwa_streams_watersheds_lut` / `fwa_watersheds_upstream_area` (LEFT JOIN `area`)
  - an area of 0
  - a watershed group whose median is NULL or 0

  If the upstream-area table is empty or only partly loaded (it is a separate prerequisite, README:19), the test passes with 0 small and 0 big, and the report shows every outlet as `ok`. Today 0 of 37,040 main-stem rows have a NULL ratio, so nothing is wrong yet. Fix: also require that the ratios exist, e.g. `AND count(*) FILTER (WHERE main_stem AND (density_ratio IS NULL OR runoff_ratio IS NULL)) = 0` (or a small ceiling). Optionally give those rows their own label in the report so they are not called `ok`.

- **[severity: fragile]** extras/pcic_crosswalk/sql/qa_drainage.sql:26-27. The header comment gives stale numbers: "217 'small' ... 123 'big'". The README (line 107), the qa.sql comment (line 123), findings.md and the table in the local DB all say **218 small / 124 big**. I checked the DB: small 218, big 124, ok 36,698, so 37,040 main-stem rows, plus 627 side-channel rows, 37,667 in all, which equals the placed count. The ceilings in qa.sql are justified by the measured counts, so the two places that state them should agree.

## Verified, no issue

- **Recursive subtree (`up`):** the join is only to `pcic_rivers`. Lakes are never measured, so no polygon perimeters get in. `pcic_outlets.subid` is a primary key, and `root_subid IS NULL` = 0 and self-loops = 0, so there are no cycles today. The same recursion from every outlet already exists in `pcic_crosswalk03_prepare.sql:9`, so a cycle would hang the job there first. Nothing new.
- **No double counting:** `(subid, member)` pairs are unique on a tree, and the river rows per member are summed once.
- **`ADD PRIMARY KEY (subid)` is safe:** the lut's key is `linear_feature_id`, and rank-1 candidates are unique per subid (checked: no duplicates; ranks are re-assigned with `row_number()`).
- **Zero or NULL guards:** the median uses only `fwa_area_km2 > 0`, and both ratios use `nullif` on the area and on the median. One outlet (8001797) shows area 0.00 after rounding. The ratio uses the unrounded value, so it is flagged `big` correctly.
- **Step 5 ordering:** qa_drainage.sql runs after step 4, before qa.sql and before the staging DROP. `set -e` plus `ON_ERROR_STOP=1` stop the job if it fails. The `\copy` to `data/qa_drainage.csv` is relative to the working directory, like every other `sql/` and `data/` path in the script, and `data/` is created at line 13.
- **README and findings numbers checked against the DB:**
  - 218 small / 124 big of 37,040: match
  - "82 of the 85" outlets over 10 times PCIC flagged `small`, all 85 on main stems: match
  - edge-type breakdowns: match

## Note (not a defect)

- Each outlet is normalised by the median of its own watershed group's main-stem placements. 6 of 195 groups have fewer than 10 such placements, and the smallest has 3. In those groups one misplaced outlet moves the median it is judged against, so the check is nearly blind there. This is a limit of the design, not a bug. It may be worth one line in the README alongside "flags are a review list".
