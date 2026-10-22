-- The Hope fixture as an origin (#34): Fraser, blue line 356364114, measure
-- 160400, grp 'hope'. docs/03_functions.md gives 161.40 km of main flow below
-- it and 308.54 km in all (sum of st_length over the returned segments).

DELETE FROM fwapg.bench_origins WHERE grp = 'hope';

INSERT INTO fwapg.bench_origins (
  grp, rnk, linear_feature_id, blue_line_key, seg_drm, measure, wscode_ltree, localcode_ltree,
  watershed_group_code, edge_type, in_tree, has_path, in_fwa_streams
)
SELECT 'hope', 1, s.linear_feature_id, s.blue_line_key, s.downstream_route_measure, 160400,
  s.wscode_ltree, s.localcode_ltree, s.watershed_group_code, s.edge_type,
  EXISTS (SELECT 1 FROM whse_basemapping.fwa_stream_networks_mainflow_tree t WHERE t.linear_feature_id = s.linear_feature_id),
  EXISTS (SELECT 1 FROM fwapg.blk_paths p WHERE p.blue_line_key = s.blue_line_key),
  EXISTS (SELECT 1 FROM whse_basemapping.fwa_streams f WHERE f.linear_feature_id = s.linear_feature_id)
FROM whse_basemapping.fwa_stream_networks_sp s
WHERE s.blue_line_key = 356364114
AND s.downstream_route_measure <= 160400
ORDER BY s.downstream_route_measure DESC
LIMIT 1;

SELECT 'hope origin', format('segment %s, seg_drm %s, in tree %s, has path %s', linear_feature_id, round(seg_drm::numeric, 3), in_tree, has_path)
FROM fwapg.bench_origins WHERE grp = 'hope';
