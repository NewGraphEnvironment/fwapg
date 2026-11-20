-- Where a side channel flows into main flow, the share of the confluence it
-- carries: its area over the areas of all segments flowing into the same
-- segment (the side/mouth CTEs of ../../sql/qa.sql), with the tree's area and
-- with the watershed lookup's (fwa_streams_watersheds_lut with
-- fwa_watersheds_upstream_area, the join of ../../sql/qa_area.sql) over the same
-- inflows. lookup_missing counts inflows with no lookup row; share_lookup is
-- NULL where any is missing. Sums in a fixed order, so a re-extract of the
-- same build writes the same digits.
WITH side AS (
  SELECT a.linear_feature_id, a.downstream_id, a.upstream_area_ha
  FROM fwapg.mainflow_tree_area a
  INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t ON t.linear_feature_id = a.linear_feature_id
  INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree d ON d.linear_feature_id = a.downstream_id
  WHERE t.source != 'mainflow' AND d.source = 'mainflow' AND a.downstream_method = 'node'
),
lk AS (
  SELECT l.linear_feature_id, ua.upstream_area_ha
  FROM whse_basemapping.fwa_streams_watersheds_lut l
  INNER JOIN whse_basemapping.fwa_watersheds_upstream_area ua ON ua.watershed_feature_id = l.watershed_feature_id
)
SELECT s.linear_feature_id, s.downstream_id,
  s.upstream_area_ha / sum(i.upstream_area_ha ORDER BY i.linear_feature_id) AS share_tree,
  CASE WHEN count(*) = count(il.upstream_area_ha)
    THEN max(sl.upstream_area_ha) / sum(il.upstream_area_ha ORDER BY i.linear_feature_id) END AS share_lookup,
  count(*) - count(il.upstream_area_ha) AS lookup_missing
FROM side s
INNER JOIN fwapg.mainflow_tree_area i ON i.downstream_id = s.downstream_id
LEFT JOIN lk il ON il.linear_feature_id = i.linear_feature_id
LEFT JOIN lk sl ON sl.linear_feature_id = s.linear_feature_id
GROUP BY s.linear_feature_id, s.downstream_id, s.upstream_area_ha
ORDER BY s.linear_feature_id;
