# Plan review (#24), Plan agent, spawned 2026-10-27 15:12Z, delivered ~15:25Z

Reviewed the plan and the committed code (46fcf91, bcf3131); read-only SELECTs on the local build.

Verdict: design correct for the Nechako case, no design blocker. Confirmed by probe: all 479 subtree outlets with a
candidate have one on or upstream of the exit (all 61 direct children); no subtree candidate on 356362759 or 356209076;
1007550 cannot be blamed by 05; 0 placed outlets outside the subtree lie above the exit; no junction at 288852.348
(nearest 288322.321 and 288931.859), so the 06 move skip is a no-op today; fwa_depth and the cycle check follow the
flow parent; 1007550's published fwa_parent_subid was already 1008709. Share arithmetic: exit 701799415 and canyon
701799355 share fundamental watershed 9934171 (13,999 km2), so the top canyon share is 0; 1002307's local area drops
from ~1,402,921 ha to ~3,100 ha; 1008709's from 0 to 84 ha; 1008709 alone on 700626260 after the move.

Findings and what was done:

1. Ordering (high): the first rebuild is refused at export (pcic_export.sql:34-61) while pcic.runs holds the
   other run on b1a71083 and pcic.series 63 rows on it. -> Confirmed by reading the export. Phase 5 gains a step:
   after the dev build, delete the 1951-2012 rows from pcic.runs, subbasin_daily, discharge_monthly/weekly and the
   PNWNAmet rows of pcic.series before the first real build.
2. Dev build dropped pcic_qa_build and pcic_qa_gauges. -> Expected; the real rebuild and qa_gauges.sh rerun restore them.
3. Gap: position parent not kept after a build. -> Kept as fwapg.pcic_qa_diversions beside pcic_qa_outlets; README
   says so; stale comments in 04 and load/pcic_schema.sql fixed.
4. Gap: coalesce fallback and a position parent equal to the anchor would double-add. -> 06 refuses both right after
   position_parent_subid is set.
5. Assumption: the receiving outlet must own its segment. -> 06 refuses otherwise.
6. Acceptance wording: canyon near the dam is 0, not 0.36; outside the subtree nothing should change at all. ->
   Verification rewritten: crosswalk rows outside the subtree identical, subbasin_daily outside the subtree equal
   within 1e-9, weights unchanged outside CHES/LNRS/LEUT/UEUT/UNRS (sets).
7. Test strength. -> Added: 08JA028's outlet 1001917 placed and within 5% of PCIC; each diversion in exactly one
   segment's upstream_subids.
8. "Show the new tests fail" cannot run on the old build (staging gone). -> The baseline numbers are the before
   evidence (exit 0.134 m3/s, 4 of 483 placed); mutation checks run on the held dev staging.
9. pcic_test.sh covers none of 03-07. -> Noted; coverage is qa.sql on a build plus the mutation checks.
10. Drainage flags by design: 1002307 small, 1008709 and 1001496 big; 1007550's distance_to_stream ~70.7 km. ->
    Listed in qa_report.sql's known cases and the README caveat after the rebuild.

Also: qa.sql:54's "Measured at 10" comment to name the Kenney Dam pair (one more drop).
