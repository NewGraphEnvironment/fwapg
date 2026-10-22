-- One pair's set differences, included by 07_compare.sql with psql variables
-- pair, ma/wa and mb/wb (method and walk of a and b), and the origin set:
-- rnk <= ohi of the random sample, and of the groups too when groups is true.
-- The set is taken from bench_origins, not from the rows, so an origin one
-- method returns nothing for still counts.

INSERT INTO fwapg.bench_diffs (pair, kind, origin_id, linear_feature_id, in_a, in_b)
SELECT :'pair', 'set',
  coalesce(a.origin_id, b.origin_id),
  coalesce(a.linear_feature_id, b.linear_feature_id),
  a.origin_id IS NOT NULL,
  b.origin_id IS NOT NULL
FROM (
  SELECT r.origin_id, r.linear_feature_id
  FROM fwapg.bench_res r
  INNER JOIN fwapg.bench_origins o ON o.origin_id = r.origin_id
  WHERE r.method = :'ma' AND r.walk = :'wa'
  AND o.rnk <= :ohi AND (o.grp = 'random' OR (:groups AND o.grp IN ('ADMS', 'BULK', 'LFRA')))
) a
FULL JOIN (
  SELECT r.origin_id, r.linear_feature_id
  FROM fwapg.bench_res r
  INNER JOIN fwapg.bench_origins o ON o.origin_id = r.origin_id
  WHERE r.method = :'mb' AND r.walk = :'wb'
  AND o.rnk <= :ohi AND (o.grp = 'random' OR (:groups AND o.grp IN ('ADMS', 'BULK', 'LFRA')))
) b ON a.origin_id = b.origin_id AND a.linear_feature_id = b.linear_feature_id
WHERE a.origin_id IS NULL OR b.origin_id IS NULL;
