-- fwapg#4 Phase 1: FWA_WatershedAtMeasure() at the issue's nine points on four
-- Skeena side channels. One row per point: rows returned, area, refine method,
-- or the error raised.
\set ON_ERROR_STOP 0
\pset format unaligned
\pset tuples_only on
SELECT format($f$
  SELECT %s AS blue_line_key, %s AS measure,
    (SELECT s.edge_type FROM whse_basemapping.fwa_stream_networks_sp s
     WHERE s.blue_line_key = %s AND s.downstream_route_measure <= %s
     ORDER BY s.downstream_route_measure DESC LIMIT 1) AS edge_type,
    count(*) AS n_rows, round(sum(area_ha)::numeric / 100, 1) AS km2,
    string_agg(DISTINCT refine_method, ',') AS refine_method
  FROM whse_basemapping.fwa_watershedatmeasure(%s, %s);
$f$, p.blk, p.m, p.blk, p.m, p.blk, p.m)
FROM (VALUES
  (360216952, 1100), (360216952, 1800), (360216952, 2000), (360216952, 2400),
  (360216952, 2700), (360216952, 3000), (360216952, 3300),
  (360222215, 60), (360237491, 150), (360222216, 1400)
) AS p (blk, m)
\gexec
