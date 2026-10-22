-- QA of fwapg.downstream_ids (#34). Assertions are "assert: name|t"; bench.sh
-- fails the step if any is not t. The listings after them are for findings.md.

-- the reverse walk needs the pointers indexed; created after the size was taken
CREATE INDEX IF NOT EXISTS downstream_ids_downstream_id_idx ON fwapg.downstream_ids (downstream_id);

SELECT 'assert: one row per network segment',
  (SELECT count(*) FROM fwapg.downstream_ids) = (SELECT count(*) FROM whse_basemapping.fwa_stream_networks_sp)
  AND NOT EXISTS (
    SELECT 1 FROM whse_basemapping.fwa_stream_networks_sp s
    WHERE NOT EXISTS (SELECT 1 FROM fwapg.downstream_ids d WHERE d.linear_feature_id = s.linear_feature_id)
  );

SELECT 'assert: no segment points to itself',
  NOT EXISTS (SELECT 1 FROM fwapg.downstream_ids WHERE downstream_id = linear_feature_id);

SELECT 'assert: every downstream_id is a segment',
  NOT EXISTS (
    SELECT 1 FROM fwapg.downstream_ids d
    WHERE d.downstream_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM fwapg.downstream_ids t WHERE t.linear_feature_id = d.downstream_id)
  );

SELECT 'assert: method and step_m are set exactly when downstream_id is',
  NOT EXISTS (
    SELECT 1 FROM fwapg.downstream_ids
    WHERE (downstream_id IS NULL) != (method IS NULL)
    OR (downstream_id IS NULL) != (step_m IS NULL)
  );

SELECT 'assert: step_m is positive',
  NOT EXISTS (SELECT 1 FROM fwapg.downstream_ids WHERE step_m <= 0);

-- acyclic and complete: one walk up from the roots reaches every row exactly
-- once. A segment on a cycle is never reached (its only way down stays in the
-- cycle), so the count falls short; in a forest no row is reached twice.
CREATE TEMPORARY TABLE qa_reached AS
WITH RECURSIVE up AS (
  SELECT linear_feature_id
  FROM fwapg.downstream_ids
  WHERE downstream_id IS NULL
  UNION ALL
  SELECT d.linear_feature_id
  FROM up
  INNER JOIN fwapg.downstream_ids d ON d.downstream_id = up.linear_feature_id
)
SELECT linear_feature_id FROM up;

SELECT 'assert: the walk up from the roots reaches every segment once (acyclic, complete)',
  (SELECT count(*) FROM qa_reached) = (SELECT count(*) FROM fwapg.downstream_ids)
  AND (SELECT count(DISTINCT linear_feature_id) FROM qa_reached) = (SELECT count(*) FROM fwapg.downstream_ids);

SELECT 'assert: a tree segment points off the tree only where the tree QA logs it',
  NOT EXISTS (
    SELECT 1
    FROM fwapg.downstream_ids d
    INNER JOIN fwapg.downstream_ids t ON t.linear_feature_id = d.downstream_id
    WHERE d.in_tree AND NOT t.in_tree
    AND NOT EXISTS (SELECT 1 FROM fwapg.mainflow_tree_qa q WHERE q.linear_feature_id = d.linear_feature_id)
  );

-- listings

SELECT 'roots (null downstream_id)', format('%s; in tree %s', count(*), count(*) FILTER (WHERE in_tree))
FROM fwapg.downstream_ids
WHERE downstream_id IS NULL;

SELECT 'method ' || coalesce(method, 'null') || CASE WHEN in_tree THEN ', in tree' ELSE ', not in tree' END, count(*)
FROM fwapg.downstream_ids
GROUP BY method, in_tree
ORDER BY method NULLS LAST, in_tree DESC;

SELECT 'node pointers that leave the blue line while the line continues', count(*)
FROM fwapg.downstream_ids d
INNER JOIN whse_basemapping.fwa_stream_networks_sp s ON s.linear_feature_id = d.linear_feature_id
INNER JOIN whse_basemapping.fwa_stream_networks_sp t ON t.linear_feature_id = d.downstream_id
WHERE d.method = 'node'
AND t.blue_line_key != s.blue_line_key
AND EXISTS (
  SELECT 1 FROM whse_basemapping.fwa_stream_networks_sp n
  WHERE n.blue_line_key = s.blue_line_key
  AND n.downstream_route_measure < s.downstream_route_measure
);

SELECT 'of those, by source in tree', string_agg(k || ' ' || n, ', ')
FROM (
  SELECT CASE WHEN d.in_tree THEN 'in tree' ELSE 'not in tree' END AS k, count(*) AS n
  FROM fwapg.downstream_ids d
  INNER JOIN whse_basemapping.fwa_stream_networks_sp s ON s.linear_feature_id = d.linear_feature_id
  INNER JOIN whse_basemapping.fwa_stream_networks_sp t ON t.linear_feature_id = d.downstream_id
  WHERE d.method = 'node'
  AND t.blue_line_key != s.blue_line_key
  AND EXISTS (
    SELECT 1 FROM whse_basemapping.fwa_stream_networks_sp n
    WHERE n.blue_line_key = s.blue_line_key
    AND n.downstream_route_measure < s.downstream_route_measure
  )
  GROUP BY 1
) x;

SELECT 'tree QA ' || q.kind || ' by pointer',
  string_agg(x.k || ' ' || x.n, ', ' ORDER BY x.k)
FROM (SELECT DISTINCT kind FROM fwapg.mainflow_tree_qa) q
CROSS JOIN LATERAL (
  SELECT
    coalesce(d.method, 'null') || CASE WHEN t.in_tree THEN ' to tree' WHEN t.linear_feature_id IS NOT NULL THEN ' off tree' ELSE '' END AS k,
    count(*) AS n
  FROM fwapg.mainflow_tree_qa m
  INNER JOIN fwapg.downstream_ids d ON d.linear_feature_id = m.linear_feature_id
  LEFT JOIN fwapg.downstream_ids t ON t.linear_feature_id = d.downstream_id
  WHERE m.kind = q.kind
  GROUP BY 1
) x
GROUP BY q.kind
ORDER BY q.kind;

-- the 8 cut-offs, one line each
SELECT 'cut_off ' || m.linear_feature_id,
  format('%s %s blk %s -> %s (%s, blk %s, %s), step %s m',
    m.watershed_group_code, CASE WHEN m.mainflow THEN 'main flow' ELSE 'side' END, m.blue_line_key,
    d.downstream_id, d.method, t.blue_line_key,
    CASE WHEN dt.in_tree THEN 'in tree' ELSE 'not in tree' END,
    round(d.step_m::numeric, 3))
FROM fwapg.mainflow_tree_qa m
INNER JOIN fwapg.downstream_ids d ON d.linear_feature_id = m.linear_feature_id
LEFT JOIN fwapg.downstream_ids dt ON dt.linear_feature_id = d.downstream_id
LEFT JOIN whse_basemapping.fwa_stream_networks_sp t ON t.linear_feature_id = d.downstream_id
WHERE m.kind = 'cut_off'
ORDER BY m.linear_feature_id;

-- the Beaver River override: the excluded 6010 connector and the segments that
-- reach its node
SELECT 'beaver override ' || o.linear_feature_id,
  format('excluded connector: in tree %s, -> %s (%s)', d.in_tree, d.downstream_id, d.method)
FROM fwapg.mainflow_tree_overrides o
INNER JOIN fwapg.downstream_ids d ON d.linear_feature_id = o.linear_feature_id;

SELECT 'beaver override upstream of ' || o.linear_feature_id,
  string_agg(u.linear_feature_id || ' (' || u.method || CASE WHEN u.in_tree THEN ', tree' ELSE '' END || ')', ', ')
FROM fwapg.mainflow_tree_overrides o
INNER JOIN fwapg.downstream_ids u ON u.downstream_id = o.linear_feature_id
GROUP BY o.linear_feature_id;
