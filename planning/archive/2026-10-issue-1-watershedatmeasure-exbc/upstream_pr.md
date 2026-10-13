# Upstream PR — as posted

Title: Restore exbc CTE in non-lake path of FWA_WatershedAtMeasure

Head: `NewGraphEnvironment:fix-watershedatmeasure-exbc` (fb52a89; the commits were reworded to drop the `Claude-Session:` trailer, and the tree is unchanged from fc63f79). Option 1 (restore the CTE) was sent; option 2 is offered in the body. No upstream issue was filed, by the operator's decision. An earlier, longer draft is in git history.

---

#185 removed the `exbc` CTE from the non-lake path of `whse_basemapping.fwa_watershedatmeasure` but left the `UNION ALL ... FROM exbc` in `agg` (`schema.sql:3929`). Every non-lake call on a loaded db now fails:

```
=# SELECT area_ha FROM whse_basemapping.fwa_watershedatmeasure(360873822, 166030);
ERROR:  relation "exbc" does not exist
```

This PR restores the CTE as a migration (the first in `db/migrations/`), plus the same 16 lines in `schema.sql` so fresh installs work. Drop the `schema.sql` commit if you'd rather regenerate it. The function body is then identical to the `postgisftw` copy.

If dropping hydrosheds/NHD was the intent (#184), the alternative is to delete the dangling `UNION ALL` instead. It gives the same result on a standard load, and I'm happy to switch.

Tested on a loaded db: the areas below are with the fix; without it, the Bulkley call raises the error above. The migration applies cleanly on a db built from `schema.sql`, and a second run does nothing.

| point | area_ha |
|---|---|
| Bulkley R. `(360873822, 166030)` | 231944.70 |
| Kootenay R. `(356570348, 160000)` | 3469676.93 |
| Kootenay Lake `(356570348, 110000)` | 4650676.78 |
| Columbia R. `(356570372, 1203700)` | 8743886.64 |

🤖 Generated with [Claude Code](https://claude.com/claude-code)
