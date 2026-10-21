-- Origins for #34, written once. An origin is a segment's midpoint.
--
-- grp 'random': 100,000 segments drawn from the province; grp ADMS, BULK, LFRA:
-- every segment of the watershed group. Eligible segments have both codes and a
-- watershed code not under 999 (not on the network). rnk is a stable seeded rank
-- (md5 of a fixed seed and the id, no dependence on scan order), so the subsets
-- nest: random 1..20 is in 1..100, in 1..1,000, in 1..10,000; and each group's
-- 1..1,000 is its seeded subsample.

DROP TABLE IF EXISTS fwapg.bench_origins;

CREATE TABLE fwapg.bench_origins (
  origin_id serial PRIMARY KEY,
  grp text NOT NULL,
  rnk integer NOT NULL,
  linear_feature_id bigint NOT NULL,
  blue_line_key integer NOT NULL,
  seg_drm double precision NOT NULL,   -- the origin segment's downstream_route_measure
  measure double precision NOT NULL,   -- the segment's midpoint
  wscode_ltree ltree NOT NULL,
  localcode_ltree ltree NOT NULL,
  watershed_group_code text NOT NULL,
  edge_type integer NOT NULL,
  in_tree boolean NOT NULL,
  has_path boolean NOT NULL,
  in_fwa_streams boolean NOT NULL,
  UNIQUE (grp, rnk)
);

CREATE TEMPORARY TABLE eligible AS
SELECT
  s.linear_feature_id,
  s.blue_line_key,
  s.downstream_route_measure,
  s.upstream_route_measure,
  s.wscode_ltree,
  s.localcode_ltree,
  s.watershed_group_code,
  s.edge_type,
  md5('fwapg#34:' || s.linear_feature_id) AS seed_key
FROM whse_basemapping.fwa_stream_networks_sp s
WHERE s.wscode_ltree IS NOT NULL
AND s.localcode_ltree IS NOT NULL
AND NOT s.wscode_ltree <@ '999';

INSERT INTO fwapg.bench_origins (
  grp, rnk, linear_feature_id, blue_line_key, seg_drm, measure, wscode_ltree, localcode_ltree,
  watershed_group_code, edge_type, in_tree, has_path, in_fwa_streams
)
SELECT
  x.grp,
  x.rnk,
  e.linear_feature_id,
  e.blue_line_key,
  e.downstream_route_measure,
  (e.downstream_route_measure + e.upstream_route_measure) / 2,
  e.wscode_ltree,
  e.localcode_ltree,
  e.watershed_group_code,
  e.edge_type,
  EXISTS (SELECT 1 FROM whse_basemapping.fwa_stream_networks_mainflow_tree t WHERE t.linear_feature_id = e.linear_feature_id),
  EXISTS (SELECT 1 FROM fwapg.blk_paths p WHERE p.blue_line_key = e.blue_line_key),
  EXISTS (SELECT 1 FROM whse_basemapping.fwa_streams f WHERE f.linear_feature_id = e.linear_feature_id)
FROM (
  SELECT linear_feature_id, 'random' AS grp, row_number() OVER (ORDER BY seed_key, linear_feature_id) AS rnk
  FROM eligible
  UNION ALL
  SELECT linear_feature_id, watershed_group_code,
    row_number() OVER (PARTITION BY watershed_group_code ORDER BY seed_key, linear_feature_id)
  FROM eligible
  WHERE watershed_group_code IN ('ADMS', 'BULK', 'LFRA')
) x
INNER JOIN eligible e ON e.linear_feature_id = x.linear_feature_id
WHERE x.grp != 'random' OR x.rnk <= 100000;

ANALYZE fwapg.bench_origins;

SELECT 'origins ' || grp,
  format('%s; in tree %s, with a path %s, in fwa_streams %s, edge 6010 %s',
    count(*),
    count(*) FILTER (WHERE in_tree),
    count(*) FILTER (WHERE has_path),
    count(*) FILTER (WHERE in_fwa_streams),
    count(*) FILTER (WHERE edge_type = 6010))
FROM fwapg.bench_origins
GROUP BY grp
ORDER BY grp;

SELECT 'random 1..1000', format('in tree %s, with a path %s, in fwa_streams %s',
  count(*) FILTER (WHERE in_tree), count(*) FILTER (WHERE has_path), count(*) FILTER (WHERE in_fwa_streams))
FROM fwapg.bench_origins
WHERE grp = 'random' AND rnk <= 1000;

SELECT 'excluded (null or 999 code)', format('province %s, ADMS %s, BULK %s, LFRA %s',
  count(*),
  count(*) FILTER (WHERE watershed_group_code = 'ADMS'),
  count(*) FILTER (WHERE watershed_group_code = 'BULK'),
  count(*) FILTER (WHERE watershed_group_code = 'LFRA'))
FROM whse_basemapping.fwa_stream_networks_sp
WHERE wscode_ltree IS NULL OR localcode_ltree IS NULL OR wscode_ltree <@ '999';
