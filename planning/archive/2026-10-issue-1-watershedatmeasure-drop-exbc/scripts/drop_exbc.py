import re, sys
p = sys.argv[1]
s = open(p).read()
COMMENT = r"        -- find any upstream contributing area outside of BC \(but not including Alaska panhandle\)\n        exbc AS\n         \(\n(?:(?!        \)).*\n)*?"
edits = [
  # lake path: exbc is the last CTE, so drop the comma after prelim too
  ("lake CTE", r"        \),\n\n" + COMMENT + r"        \)\n", "        )\n", 2),
  # river path: exbc sits between cut and agg
  ("river CTE", COMMENT + r"        \),\n\n", "", int(sys.argv[2])),
  ("river branch", r"        -- add watersheds outside of BC\n        UNION ALL\n          SELECT\n            ST_Difference\(exbc\.geom, bc\.geom\) as geom\n          FROM exbc\n          INNER JOIN whse_basemapping\.fwa_bcboundary bc\n          ON ST_Intersects\(exbc\.geom, bc\.geom\)\n\n", "", 2),
  ("lake branch", r"          UNION ALL\n          SELECT\n            ST_Difference\(exbc\.geom, bc\.geom\) as geom\n          FROM exbc\n          INNER JOIN whse_basemapping\.fwa_bcboundary bc\n          ON ST_Intersects\(exbc\.geom, bc\.geom\)\n", "", 2),
]
for name, pat, rep, want in edits:
    s, n = re.subn(pat, rep, s)
    if n != want:
        sys.exit(f"{name}: {n} matches, expected {want}")
    print(name, n)
assert "exbc" not in s
open(p, "w").write(s)
