INSTALL httpfs; LOAD httpfs;
SET VARIABLE base = 'https://fresh-bc.s3.us-west-2.amazonaws.com/fwapg/extras/';
SET VARIABLE files = (
  SELECT list(getvariable('base') || 'pcic.subbasin_days.PNWNAmet_historical.' || y || '.parquet')
  FROM range(1951, 2013) t(y)
);
CREATE OR REPLACE TEMP TABLE weights AS
SELECT linear_feature_id, subid, share,
  list_transform(list_filter(string_split(trim(upstream_subids, '{}'), ','), x -> x != ''), x -> x::INTEGER) AS upstream_subids
FROM read_csv(getvariable('base') || 'pcic.segment_weights.csv.gz', header = true,
  columns = {'linear_feature_id': 'BIGINT', 'watershed_group_code': 'VARCHAR', 'subid': 'INTEGER', 'share': 'DOUBLE', 'upstream_subids': 'VARCHAR'})
WHERE watershed_group_code = 'BULK';
WITH needed AS (
  SELECT subid FROM weights UNION SELECT unnest(upstream_subids) FROM weights
),
days AS (
  SELECT subid, year(date) AS year, avg(q_local) AS q_local, avg(q_acc) AS q_acc
  FROM read_parquet(getvariable('files'))
  WHERE subid IN (SELECT subid FROM needed)
  AND strftime(date, '%m-%d') BETWEEN '07-15' AND '09-07'
  GROUP BY subid, year
),
up AS (
  SELECT u.linear_feature_id, d.year, sum(d.q_acc) AS q_acc
  FROM (SELECT linear_feature_id, unnest(upstream_subids) AS subid FROM weights) u
  INNER JOIN days d ON d.subid = u.subid
  GROUP BY u.linear_feature_id, d.year
)
SELECT w.linear_feature_id, s.year,
  greatest(coalesce(up.q_acc, 0) + s.q_local * w.share, 0) AS q_m3s
FROM weights w
INNER JOIN days s ON s.subid = w.subid
LEFT JOIN up ON up.linear_feature_id = w.linear_feature_id AND up.year = s.year
ORDER BY w.linear_feature_id, s.year;
