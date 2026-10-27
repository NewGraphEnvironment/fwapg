# Read one published year back over HTTP with duckdb and check it against its row
# in the published catalogue (pcic.series.csv.gz): rows, sub-basins, bytes and both
# sums, each sum(floor(double(v) * 1000 + 0.5)) over the stored float32 values.
#
# Rscript readback_http.R <year>
year <- as.integer(commandArgs(trailingOnly = TRUE)[1])
base <- "https://fresh-bc.s3.us-west-2.amazonaws.com/fwapg/extras/"
f <- sprintf("%spcic.subbasin_days.PNWNAmet_historical.%d.parquet", base, year)
t0 <- Sys.time()
con <- DBI::dbConnect(duckdb::duckdb())
DBI::dbExecute(con, "INSTALL httpfs; LOAD httpfs")
cat_row <- DBI::dbGetQuery(con, sprintf(
  "SELECT * FROM read_csv('%spcic.series.csv.gz', header = true, all_varchar = true)
   WHERE model = 'PNWNAmet' AND scenario = 'historical' AND year = '%d'", base, year))
stopifnot(nrow(cat_row) == 1)
h <- curl::curl_fetch_memory(f, curl::new_handle(nobody = TRUE))
bytes <- as.numeric(curl::parse_headers_list(h$headers)[["content-length"]])
got <- DBI::dbGetQuery(con, sprintf("
  SELECT count(*) AS rows, count(DISTINCT subid) AS subbasins,
    sum(floor(CAST(q_local AS DOUBLE) * 1000 + 0.5))::BIGINT::VARCHAR AS q_local_sum,
    sum(floor(CAST(q_acc AS DOUBLE) * 1000 + 0.5))::BIGINT::VARCHAR AS q_acc_sum,
    min(date) AS first, max(date) AS last
  FROM read_parquet('%s')", f))
meta <- DBI::dbGetQuery(con, sprintf(
  "SELECT decode(key) AS key, decode(value) AS value FROM parquet_kv_metadata('%s')
   WHERE decode(key) LIKE 'fwapg.%%'", f))
el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
print(cat_row[, c("year", "rows", "subbasins", "q_local_sum", "q_acc_sum", "bytes", "crosswalk_md5", "commit")])
print(got); print(meta); cat("content-length", format(bytes, scientific = FALSE), "\n")
ok <- c(
  rows = got$rows == as.numeric(cat_row$rows),
  subbasins = got$subbasins == as.numeric(cat_row$subbasins),
  bytes = bytes == as.numeric(cat_row$bytes),
  q_local_sum = got$q_local_sum == cat_row$q_local_sum,
  q_acc_sum = got$q_acc_sum == cat_row$q_acc_sum,
  crosswalk_md5 = meta$value[meta$key == "fwapg.crosswalk_md5"] == cat_row$crosswalk_md5,
  commit = meta$value[meta$key == "fwapg.commit"] == cat_row$commit)
print(ok)
cat(sprintf("duckdb %s, R %s, curl %s, elapsed %.1f s\n", packageVersion("duckdb"), getRversion(),
  packageVersion("curl"), el))
DBI::dbDisconnect(con, shutdown = TRUE)
if (!all(ok)) quit(status = 1)
