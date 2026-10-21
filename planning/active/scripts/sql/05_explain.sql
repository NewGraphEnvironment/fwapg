-- EXPLAIN (ANALYZE, BUFFERS) of every method and walk at 1 and 1,000 origins
-- (#34): the single-origin plan is not necessarily the batch plan. Run by
-- `bench.sh explain` from this directory, after a cell has warmed the cache.
-- L1 is a plpgsql function, so its plan is one Function Scan: shown at one
-- origin only. A-pred at 1,000 origins evaluates the predicate for every
-- (origin, segment) pair and is shown without ANALYZE.

SET statement_timeout = '30min';
\set out fwapg.bench_out
\set grp random

\set explain 'EXPLAIN (ANALYZE, BUFFERS, SETTINGS)'

\set lo 1
\set hi 1
\echo '== L1 full, 1 origin'
\set method L1
\set walk full
TRUNCATE fwapg.bench_out;
\ir 02_walk_ltree.sql

\echo '== L2 full, 1 origin'
\set method L2
TRUNCATE fwapg.bench_out;
\ir 02_walk_ltree.sql

\echo '== A-pred full, 1 origin'
\set method A-pred
TRUNCATE fwapg.bench_out;
\ir 03_walk_arrays.sql

\echo '== A full, 1 origin'
\set method A
TRUNCATE fwapg.bench_out;
\ir 03_walk_arrays.sql

\echo '== A 1km, 1 origin'
\set walk 1km
TRUNCATE fwapg.bench_out;
\ir 03_walk_arrays.sql

\echo '== P full, 1 origin'
\set method P
\set walk full
TRUNCATE fwapg.bench_out;
\ir 04_walk_pointer.sql

\echo '== P 1km, 1 origin'
\set walk 1km
TRUNCATE fwapg.bench_out;
\ir 04_walk_pointer.sql

\set hi 1000
\echo '== L2 full, 1,000 origins'
\set method L2
\set walk full
TRUNCATE fwapg.bench_out;
\ir 02_walk_ltree.sql

\echo '== A-pred full, 1,000 origins (no ANALYZE)'
\set method A-pred
\set explain 'EXPLAIN'
\ir 03_walk_arrays.sql
\set explain 'EXPLAIN (ANALYZE, BUFFERS, SETTINGS)'

\echo '== A full, 1,000 origins'
\set method A
TRUNCATE fwapg.bench_out;
\ir 03_walk_arrays.sql

\echo '== A 1km, 1,000 origins'
\set walk 1km
TRUNCATE fwapg.bench_out;
\ir 03_walk_arrays.sql

\echo '== P full, 1,000 origins'
\set method P
\set walk full
TRUNCATE fwapg.bench_out;
\ir 04_walk_pointer.sql

\echo '== P 1km, 1,000 origins'
\set walk 1km
TRUNCATE fwapg.bench_out;
\ir 04_walk_pointer.sql

TRUNCATE fwapg.bench_out;
