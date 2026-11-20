-- fwapg#4: at every place a side channel (a reattached or followed segment)
-- flows into main flow, the share of the confluence it carries: its area over
-- the areas of the tree segments that flow into the same segment. This is the
-- segment proportional influence SSNbler would compute there. With the tree's
-- area, and with the watershed lookup's on the same segments.
\pset format unaligned
\pset tuples_only on
WITH mouth AS (
  SELECT a.linear_feature_id, a.downstream_id, a.upstream_area_ha
  FROM fwapg.mainflow_tree_area a
  INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree t ON t.linear_feature_id = a.linear_feature_id
  INNER JOIN whse_basemapping.fwa_stream_networks_mainflow_tree d ON d.linear_feature_id = a.downstream_id
  WHERE t.source != 'mainflow' AND d.source = 'mainflow' AND a.downstream_method = 'node'
),
lookup AS (
  SELECT l.linear_feature_id, ua.upstream_area_ha
  FROM whse_basemapping.fwa_streams_watersheds_lut l
  INNER JOIN whse_basemapping.fwa_watersheds_upstream_area ua ON ua.watershed_feature_id = l.watershed_feature_id
),
share AS (
  SELECT m.linear_feature_id,
    count(*) AS inflows,
    m.upstream_area_ha / sum(i.upstream_area_ha) AS tree_share,
    CASE WHEN count(li.upstream_area_ha) = count(*) THEN max(lm.upstream_area_ha) / sum(li.upstream_area_ha) END AS lookup_share
  FROM mouth m
  INNER JOIN fwapg.mainflow_tree_area i ON i.downstream_id = m.downstream_id
  LEFT JOIN lookup li ON li.linear_feature_id = i.linear_feature_id
  LEFT JOIN lookup lm ON lm.linear_feature_id = m.linear_feature_id
  GROUP BY m.linear_feature_id, m.upstream_area_ha
)
SELECT 'side channel mouths on main flow', count(*),
  'meeting another segment', count(*) FILTER (WHERE inflows > 1),
  'tree share: median', round((percentile_cont(0.5) WITHIN GROUP (ORDER BY tree_share) FILTER (WHERE inflows > 1))::numeric, 4),
  'tree share under 0.2', count(*) FILTER (WHERE inflows > 1 AND tree_share < 0.2),
  'tree share 0.4 to 0.6', count(*) FILTER (WHERE inflows > 1 AND tree_share BETWEEN 0.4 AND 0.6),
  'with a lookup share', count(lookup_share) FILTER (WHERE inflows > 1),
  'lookup share: median', round((percentile_cont(0.5) WITHIN GROUP (ORDER BY lookup_share) FILTER (WHERE inflows > 1))::numeric, 4),
  'lookup share 0.4 to 0.6', count(*) FILTER (WHERE inflows > 1 AND lookup_share BETWEEN 0.4 AND 0.6),
  'lookup share under 0.2', count(*) FILTER (WHERE inflows > 1 AND lookup_share < 0.2)
FROM share;
SELECT 'test mouths', a.linear_feature_id, round((a.upstream_area_ha / (SELECT sum(i.upstream_area_ha) FROM fwapg.mainflow_tree_area i WHERE i.downstream_id = a.downstream_id))::numeric, 4)
FROM fwapg.mainflow_tree_area a WHERE a.linear_feature_id IN (123041439, 87082084, 87078272, 87081693) ORDER BY 2;
