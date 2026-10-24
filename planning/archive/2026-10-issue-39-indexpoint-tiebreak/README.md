## Outcome

`whse_basemapping.fwa_indexpoint()` now breaks exact distance ties. Inside `DISTINCT ON (blue_line_key)` the tie goes to the segment starting at the shared vertex (`downstream_route_measure DESC`), then to `linear_feature_id`. The outer sort uses the unrounded distance, then `linear_feature_id`. The fix is migration `db/migrations/202610240132__indexpoint_tiebreak.sql` plus three cases in `tests/test_FWA_IndexPoint.sql`, committed `d955688` on the clean upstream branch `indexpoint-tiebreak` and cherry-picked here as `aa9f6a1`.

The issue proposed the lowest id. The gate chose the upper segment instead: fwapg's `[downstream, upstream)` convention puts a measure on the vertex on that segment, and `pcic_crosswalk02_candidates.sql` already broke the same tie that way. The plan review then found that the old pick could return a measure `FWA_LocateAlong` cannot place.

The user asked mid-run whether this reaches bcfishpass and bcfishobs. It does not: neither calls the function. Both carry the same untied pick in their own SQL, and that was measured too. The upstream PR is drafted and not posted, and the local fwapg is not migrated; both wait on the user. Durable findings: `research/fwa_position_codes.md`, "A point on a shared vertex is equally near two segments".

## Measurement

Every run was on a loaded provincial fwapg, inside a transaction that rolled back.

- **Tests:** 10 of 10 `t` with the migration applied. The old function fails 2: the 08KD006 segment, and `FWA_LocateAlong` at its measure (0 rows; 14040.005812552621 against the next segment's start of 14040.0058125527).
- **The old pick depends on the plan:** with index and bitmap scans off, 08EC013 moves from 5086970 to 5086038 on the real table. Temp copies in ascending and descending physical order did not flip under the same plan; with scans off, both gauges flipped there. The new body returned the upper segment in every run.
- **How often ties happen:** old against new, 5 streams per point. 9 of 242 random points and 57 of 1,000 points near segment ends changed segment. All 66 were exact float ties and all went to the upper segment. 65 were adjacent. Localcode differed in 32 and wscode in 0. The measure moved at most 3.5e-9 m. In 44 of the 66, the old id and the old measure named different segments. The stream set never changed; one point reordered two streams tied at 40.259 m after rounding. These counts are a floor.
- **bcfishobs's own tie:** 7,198 of 307,121 observations (2.34%) are exactly as near another segment of their stream as their stored one, and 3,464 (1.13%) at a tie where the localcodes differ. A 5,000-row sample gave 2.4% and 1.4% in 13 s. 68,841 observations were not measured, because their point ids are missing from the loaded `fiss_fish_obsrvtn_pnt_sp`. The fwapg fix does not change these.
- **Wrong turns:** expecting the issue's "lowest id"; claiming physical order alone flips the old pick, which it did not under the same plan; claiming both gauges flip on the real table, when only 08EC013 does; an `array_agg` without `ORDER BY` that showed 241 of 242 points as reordered (fixed with `WITH ORDINALITY`); a 30-minute timeout on the first bcfishobs pass, from a slow plan.

## Evidence

The ad hoc SQL ran from the session scratchpad and is not committed. Its results are in `findings.md` here, and the code-check rounds are in `review-codecheck-round*.md`.

## Owed

- Post the upstream PR, **only on the user's go-ahead**, then link it in #39
- Close #39 by hand after the newgraph merge, with a comment naming the PRs
- Apply to the local loaded fwapg **when the user says so**, with `cd db && DATABASE_URL=... ./migrate.sh`.
- Draft (not post) a note to Simon on the same tie in bcfishobs `process.sql` and bcfishpass PSCIS snapping, if the user wants one

Closed by: PR into newgraph from `39-indexpoint-tiebreak` (cherry-pick `aa9f6a1` of upstream branch commit `d955688`)
