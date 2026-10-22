-- The measurement environment for #34: settings by name (never SHOW ALL, which
-- prints data_directory and the port), table and index sizes, and the network
-- facts the pointer rules and the array bound rely on. Lines are name|value;
-- the assertions at the end are name|t.

SELECT 'setting ' || name, setting || coalesce(' ' || unit, '')
FROM pg_settings
WHERE name IN (
  'server_version', 'jit', 'max_parallel_workers_per_gather', 'max_parallel_workers',
  'work_mem', 'shared_buffers', 'effective_cache_size', 'random_page_cost',
  'hash_mem_multiplier', 'statement_timeout'
)
ORDER BY name;

SELECT 'extension ' || extname, extversion
FROM pg_extension
WHERE extname IN ('ltree', 'postgis')
ORDER BY extname;

-- tables: rows (exact), heap and total (indexes and toast included)
SELECT 'table ' || t.rel,
  format('%s rows, heap %s MB, total %s MB',
    t.n,
    round(pg_relation_size(t.rel::regclass) / 1048576.0),
    round(pg_total_relation_size(t.rel::regclass) / 1048576.0))
FROM (
  SELECT 'whse_basemapping.fwa_stream_networks_sp' AS rel, (SELECT count(*) FROM whse_basemapping.fwa_stream_networks_sp) AS n
  UNION ALL SELECT 'whse_basemapping.fwa_streams', (SELECT count(*) FROM whse_basemapping.fwa_streams)
  UNION ALL SELECT 'whse_basemapping.fwa_stream_networks_mainflow_tree', (SELECT count(*) FROM whse_basemapping.fwa_stream_networks_mainflow_tree)
  UNION ALL SELECT 'fwapg.blk_paths', (SELECT count(*) FROM fwapg.blk_paths)
  UNION ALL SELECT 'fwapg.blk_parents', (SELECT count(*) FROM fwapg.blk_parents)
) t
ORDER BY 1;

-- the indexes the downstream walks can use
SELECT 'index ' || i.indexrelid::regclass, round(pg_relation_size(i.indexrelid) / 1048576.0) || ' MB'
FROM pg_index i
WHERE i.indrelid IN (
  'whse_basemapping.fwa_stream_networks_sp'::regclass,
  'whse_basemapping.fwa_streams'::regclass,
  'fwapg.blk_paths'::regclass,
  'fwapg.blk_parents'::regclass
)
AND (
  i.indexrelid::regclass::text ~ '(wsc|lc)_(gist|btree)_idx$'
  OR i.indexrelid::regclass::text ~ '(blkey_measure_idx|_pkey)$'
)
ORDER BY 1;

-- network facts
SELECT 'segments absent from fwa_streams', count(*)
FROM whse_basemapping.fwa_stream_networks_sp s
WHERE NOT EXISTS (SELECT 1 FROM whse_basemapping.fwa_streams f WHERE f.linear_feature_id = s.linear_feature_id);

SELECT 'segments not in the main-flow tree', count(*)
FROM whse_basemapping.fwa_stream_networks_sp s
WHERE NOT EXISTS (
  SELECT 1 FROM whse_basemapping.fwa_stream_networks_mainflow_tree t
  WHERE t.linear_feature_id = s.linear_feature_id
);

SELECT 'blue lines whose lowest segment starts above 1 mm', count(*)
FROM (
  SELECT blue_line_key
  FROM whse_basemapping.fwa_stream_networks_sp
  GROUP BY blue_line_key
  HAVING min(downstream_route_measure) > 0.001
) x;

SELECT 'blue lines with no blk_paths row (segments)',
  format('%s (%s)', count(DISTINCT s.blue_line_key), count(*))
FROM whse_basemapping.fwa_stream_networks_sp s
WHERE NOT EXISTS (SELECT 1 FROM fwapg.blk_paths p WHERE p.blue_line_key = s.blue_line_key);

SELECT 'segments by class', format('edge 6010 %s, edge 1425 %s, code under 999 %s, null code %s',
  count(*) FILTER (WHERE edge_type = 6010),
  count(*) FILTER (WHERE edge_type = 1425),
  count(*) FILTER (WHERE wscode_ltree <@ '999'),
  count(*) FILTER (WHERE wscode_ltree IS NULL OR localcode_ltree IS NULL))
FROM whse_basemapping.fwa_stream_networks_sp;

SELECT 'blk_paths path length', format('mean %s lines, max %s',
  round(avg(cardinality(path_blks)), 2), max(cardinality(path_blks)))
FROM fwapg.blk_paths;

SELECT 'main-flow tree qa', string_agg(kind || ' ' || n, ', ' ORDER BY kind)
FROM (SELECT kind, count(*) AS n FROM fwapg.mainflow_tree_qa GROUP BY kind) x;

-- assertions (|t)
SELECT 'assert: no blue line has two segments at one downstream_route_measure',
  NOT EXISTS (
    SELECT 1 FROM whse_basemapping.fwa_stream_networks_sp
    GROUP BY blue_line_key, downstream_route_measure
    HAVING count(*) > 1
  );

SELECT 'assert: every tree segment is a network segment',
  NOT EXISTS (
    SELECT 1 FROM whse_basemapping.fwa_stream_networks_mainflow_tree t
    WHERE NOT EXISTS (
      SELECT 1 FROM whse_basemapping.fwa_stream_networks_sp s
      WHERE s.linear_feature_id = t.linear_feature_id
    )
  );
