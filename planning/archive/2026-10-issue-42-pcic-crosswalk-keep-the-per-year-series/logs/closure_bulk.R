# Direct closure for one watershed group: the 1951-2012 mean of the per-year
# files, routed per month through pcic.segment_weights, against
# pcic.discharge_monthly's 1951-2012 run.
#
# Rscript closure_bulk.R <days dir> <weights csv> <monthly csv> [wsg]
#   weights csv: linear_feature_id,subid,share,upstream_subids for the group
#   monthly csv: linear_feature_id,month,q_m3s for the group's 1951-2012 run
args <- commandArgs(trailingOnly = TRUE)
dir <- args[1]; wcsv <- args[2]; mcsv <- args[3]
t0 <- Sys.time()
con <- DBI::dbConnect(duckdb::duckdb())
files <- file.path(dir, sprintf("pcic.subbasin_days.PNWNAmet_historical.%d.parquet", 1951:2012))
stopifnot(all(file.exists(files)))
DBI::dbExecute(con, sprintf("SET VARIABLE files = [%s]", paste0("'", files, "'", collapse = ",")))
DBI::dbExecute(con, sprintf("
CREATE TEMP TABLE weights AS
SELECT linear_feature_id, subid, share,
  list_transform(list_filter(string_split(trim(upstream_subids, '{}'), ','), x -> x != ''), x -> x::INTEGER) AS upstream_subids
FROM read_csv('%s', header = true,
  columns = {'linear_feature_id': 'BIGINT', 'subid': 'INTEGER', 'share': 'DOUBLE', 'upstream_subids': 'VARCHAR'})", wcsv))
DBI::dbExecute(con, sprintf("
CREATE TEMP TABLE pub AS SELECT * FROM read_csv('%s', header = true,
  columns = {'linear_feature_id': 'BIGINT', 'month': 'INTEGER', 'q_m3s': 'DOUBLE'})", mcsv))
r <- DBI::dbGetQuery(con, "
WITH needed AS (SELECT subid FROM weights UNION SELECT unnest(upstream_subids) FROM weights),
m AS (
  SELECT subid, month(date) AS month,
    avg(CAST(q_local AS DOUBLE)) AS q_local, avg(CAST(q_acc AS DOUBLE)) AS q_acc
  FROM read_parquet(getvariable('files'))
  WHERE subid IN (SELECT subid FROM needed)
  GROUP BY subid, month
),
up AS (
  SELECT u.linear_feature_id, m.month, sum(m.q_acc) AS q_acc
  FROM (SELECT linear_feature_id, unnest(upstream_subids) AS subid FROM weights) u
  INNER JOIN m ON m.subid = u.subid
  GROUP BY u.linear_feature_id, m.month
),
q AS (
  SELECT w.linear_feature_id, s.month,
    greatest(coalesce(up.q_acc, 0) + s.q_local * w.share, 0) AS q
  FROM weights w
  INNER JOIN m s ON s.subid = w.subid
  LEFT JOIN up ON up.linear_feature_id = w.linear_feature_id AND up.month = s.month
)
SELECT
  (SELECT count(*) FROM pub) AS n_pub,
  count(*) AS n_joined,
  count(*) FILTER (WHERE round(q.q, 5) = p.q_m3s) AS n_equal_5dp,
  max(abs(round(q.q, 5) - p.q_m3s)) AS max_abs_rounded,
  max(abs(q.q - p.q_m3s) - 5e-6) AS max_beyond_rounding,
  max(abs(q.q - p.q_m3s)) AS max_abs,
  max(abs(q.q - p.q_m3s) / greatest(p.q_m3s, 1e-5)) AS max_rel_floor,
  max(abs(q.q - p.q_m3s)) FILTER (WHERE p.q_m3s >= 1) AS max_abs_q_ge_1,
  max(abs(q.q - p.q_m3s) / p.q_m3s) FILTER (WHERE p.q_m3s >= 1) AS max_rel_q_ge_1
FROM q INNER JOIN pub p USING (linear_feature_id, month)")
print(r)
cat(sprintf("duckdb %s, R %s, elapsed %.1f s\n", packageVersion("duckdb"), getRversion(),
  as.numeric(difftime(Sys.time(), t0, units = "secs"))))
DBI::dbDisconnect(con, shutdown = TRUE)
