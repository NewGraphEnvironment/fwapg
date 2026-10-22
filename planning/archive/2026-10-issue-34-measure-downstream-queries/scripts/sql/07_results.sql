-- Results for the correctness comparison (#34), untimed: each method's rows for
-- the comparison samples, into fwapg.bench_res (method, walk). Run by
-- `bench.sh results` from this directory. The samples: random 1..1,000, each
-- group's seeded 1..1,000, and L1 on random 1..100 (its shipped trace costs
-- about 1 s an origin).

SET statement_timeout = 0;

DROP TABLE IF EXISTS fwapg.bench_res;

CREATE UNLOGGED TABLE fwapg.bench_res (
  method text NOT NULL,
  walk text NOT NULL,
  origin_id integer NOT NULL,
  linear_feature_id bigint NOT NULL,
  ord integer,
  cum_m double precision
);

CREATE TEMPORARY TABLE res_one (
  origin_id integer,
  linear_feature_id bigint,
  ord integer,
  cum_m double precision
);

\set out res_one
\set lo 1
\set hi 1000

-- every (method, walk) on each sample; L1 below
\set walk full
\set method L2
\set grp random
\ir 02_walk_ltree.sql
\set grp ADMS
\ir 02_walk_ltree.sql
\set grp BULK
\ir 02_walk_ltree.sql
\set grp LFRA
\ir 02_walk_ltree.sql
INSERT INTO fwapg.bench_res SELECT 'L2', 'full', * FROM res_one;
TRUNCATE res_one;

\set method A
\set grp random
\ir 03_walk_arrays.sql
\set grp ADMS
\ir 03_walk_arrays.sql
\set grp BULK
\ir 03_walk_arrays.sql
\set grp LFRA
\ir 03_walk_arrays.sql
INSERT INTO fwapg.bench_res SELECT 'A', 'full', * FROM res_one;
TRUNCATE res_one;

\set method P
\set grp random
\ir 04_walk_pointer.sql
\set grp ADMS
\ir 04_walk_pointer.sql
\set grp BULK
\ir 04_walk_pointer.sql
\set grp LFRA
\ir 04_walk_pointer.sql
INSERT INTO fwapg.bench_res SELECT 'P', 'full', * FROM res_one;
TRUNCATE res_one;

\set walk 1km
\set method A
\set grp random
\ir 03_walk_arrays.sql
\set grp ADMS
\ir 03_walk_arrays.sql
\set grp BULK
\ir 03_walk_arrays.sql
\set grp LFRA
\ir 03_walk_arrays.sql
INSERT INTO fwapg.bench_res SELECT 'A', '1km', * FROM res_one;
TRUNCATE res_one;

\set method P
\set grp random
\ir 04_walk_pointer.sql
\set grp ADMS
\ir 04_walk_pointer.sql
\set grp BULK
\ir 04_walk_pointer.sql
\set grp LFRA
\ir 04_walk_pointer.sql
INSERT INTO fwapg.bench_res SELECT 'P', '1km', * FROM res_one;
TRUNCATE res_one;

-- L1, the shipped trace, on random 1..100
\set walk full
\set method L1
\set grp random
\set hi 100
\ir 02_walk_ltree.sql
INSERT INTO fwapg.bench_res SELECT 'L1', 'full', * FROM res_one;
TRUNCATE res_one;

-- A-pred on random 1..20, the set A's walk should equal (its 1,000 cell is a timeout)
\set method A-pred
\set hi 20
\ir 03_walk_arrays.sql
INSERT INTO fwapg.bench_res SELECT 'A-pred', 'full', * FROM res_one;
TRUNCATE res_one;

CREATE INDEX ON fwapg.bench_res (method, walk, origin_id, linear_feature_id);
ANALYZE fwapg.bench_res;

SELECT method || ' ' || walk, format('%s rows, %s origins', count(*), count(DISTINCT origin_id))
FROM fwapg.bench_res
GROUP BY method, walk
ORDER BY method, walk;
