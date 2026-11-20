-- fwapg#4: the figures README.md and research/fwa_mainflow_tree.md quote, from
-- the build's own tables. Re-run after any change to the build and compare.
\pset format unaligned
\pset tuples_only on
SELECT 'polygons', coalesce(method, 'unassigned'), count(*), round(sum(area_ha)::numeric) FROM fwapg.mainflow_tree_area_polygons GROUP BY 2 ORDER BY 3 DESC;
SELECT 'unassigned', class, count(*), round(sum(area_ha)::numeric), round(sum(shared_ha)::numeric) FROM fwapg.mainflow_tree_area_unassigned GROUP BY 2;
SELECT 'steps', coalesce(downstream_method, 'none'), count(*) FROM fwapg.mainflow_tree_area GROUP BY 2 ORDER BY 2;
SELECT 'outlets', coalesce(q.kind, 'edge of BC'), count(*), round(sum(a.upstream_area_ha)::numeric), round(max(a.upstream_area_ha)::numeric)
FROM fwapg.mainflow_tree_area a
LEFT JOIN (SELECT DISTINCT ON (linear_feature_id) linear_feature_id, kind FROM fwapg.mainflow_tree_qa ORDER BY linear_feature_id, kind) q USING (linear_feature_id)
WHERE a.downstream_id IS NULL GROUP BY 2 ORDER BY 4 DESC;
SELECT 'total at outlets', round(sum(upstream_area_ha)::numeric), count(*), (SELECT max(depth) FROM fwapg.mainflow_tree_area) FROM fwapg.mainflow_tree_area WHERE downstream_id IS NULL;
SELECT 'side', s.blue_line_key, round(s.downstream_route_measure::numeric, 1), round(a.local_area_ha::numeric, 1), round(a.upstream_area_ha::numeric, 1)
FROM fwapg.mainflow_tree_area a INNER JOIN whse_basemapping.fwa_stream_networks_sp s USING (linear_feature_id)
WHERE s.blue_line_key IN (360222215, 360237491, 360222216, 360216952) OR s.linear_feature_id = 87078680 ORDER BY 2, 3;
SELECT 'basin', b.name, round(t.upstream_area_ha::numeric, 1),
  (SELECT round((sum(ST_Area(w.geom)) / 10000)::numeric, 1) FROM whse_basemapping.fwa_watersheds_poly w WHERE w.wscode_ltree <@ b.code)
FROM (VALUES ('Skeena', '400'::ltree), ('Nechako', '100.567134'::ltree), ('Fraser', '100'::ltree)) b (name, code)
INNER JOIN LATERAL (
  SELECT t.upstream_area_ha FROM whse_basemapping.fwa_stream_networks_sp s
  INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t USING (linear_feature_id)
  WHERE s.wscode_ltree = b.code AND s.blue_line_key = s.watershed_key ORDER BY s.downstream_route_measure LIMIT 1
) t ON true;
SELECT 'shares', count(*), round(sum(share_ha)::numeric), count(DISTINCT watershed_feature_id),
  round((percentile_cont(0.5) WITHIN GROUP (ORDER BY share_ha))::numeric, 1), round(max(share_ha)::numeric) FROM fwapg.mainflow_tree_area_shares;
SELECT 'bad code polygons', count(*), round(sum(ST_Area(geom) / 10000)::numeric) FROM whse_basemapping.fwa_watersheds_poly WHERE NOT localcode_ltree <@ wscode_ltree;
SELECT 'counts', * FROM fwapg.mainflow_tree_area_qa_counts;
SELECT 'class', source, CASE WHEN class IS NULL THEN 'not explained' WHEN class ~ ',' THEN 'several kinds' ELSE class END, count(*),
  round(sum(abs(upstream_area_ha - lookup_area_ha))::numeric) FROM fwapg.mainflow_tree_area_qa GROUP BY 2, 3 ORDER BY 4 DESC;
SELECT 'column md5', md5(string_agg(linear_feature_id || ':' || upstream_area_ha, ',' ORDER BY linear_feature_id)) FROM whse_basemapping.fwa_stream_networks_mainflow_tree;
