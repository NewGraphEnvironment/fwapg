# Upstream PR draft (needs approval before posting)

**Repo:** smnorris/fwapg, base `main`, head `NewGraphEnvironment:watershedatmeasure-drop-exbc`

**Title:** Remove exbc from FWA_WatershedAtMeasure

**Body:**

---

Replaces #199, as discussed there: rather than restoring the `exbc` CTE, this removes it.

#185 dropped the `exbc` CTE from the non-lake path of `whse_basemapping.fwa_watershedatmeasure` but left the `UNION ALL ... FROM exbc` in `agg`, so every non-lake call failed with `relation "exbc" does not exist`. This PR removes the `exbc` CTE and its `UNION ALL` from both paths of both copies (`whse_basemapping` and `postgisftw`), so neither reads hydrosheds or NHD. The two bodies are identical again.

It's a migration plus the same edit in `schema.sql`, so fresh installs work too. Drop the `schema.sql` commit if you'd rather regenerate it. The hydrosheds/usgs tables and functions are untouched (#184).

Tested on a loaded db. The geometries are byte-identical to the pre-#185 function, and the migration applies on a db built from `schema.sql` and re-runs as a no-op.

| point | area_ha |
|---|---|
| Bulkley R. `(360873822, 166030)` | 231944.70 |
| Kootenay R. `(356570348, 160000)` | 3469676.93 |
| Kootenay Lake `(356570348, 110000)` | 4650676.78 |
| Columbia R. `(356570372, 1203700)` | 8743886.64 |

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

**Closing comment on #199, after the new PR exists:**

> Closing in favour of #<new>, which removes `exbc` instead.
