# Run the README's per-year duckdb query (extracted verbatim into readme_years_query.sql)
# against the published files, as the README says to from R: every statement but the
# last through dbExecute(), the last through dbGetQuery().
sql <- paste(readLines(commandArgs(trailingOnly = TRUE)[1]), collapse = "\n")
st <- trimws(strsplit(sql, ";\\s*\n")[[1]]); st <- sub(";$", "", st[nzchar(st)])
t0 <- Sys.time()
con <- DBI::dbConnect(duckdb::duckdb())
for (s in head(st, -1)) DBI::dbExecute(con, s)
r <- DBI::dbGetQuery(con, tail(st, 1))
el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat(sprintf("%d statements; %d rows, %d segments, years %d-%d, q_m3s NA %d, q_m3s == 0 %d, median %.4g\n",
  length(st), nrow(r), length(unique(r$linear_feature_id)), min(r$year), max(r$year),
  sum(is.na(r$q_m3s)), sum(r$q_m3s == 0), median(r$q_m3s)))
print(head(r[r$linear_feature_id == max(r$linear_feature_id), ], 3))
cat(sprintf("duckdb %s, R %s, elapsed %.1f s\n", packageVersion("duckdb"), getRversion(), el))
DBI::dbDisconnect(con, shutdown = TRUE)
