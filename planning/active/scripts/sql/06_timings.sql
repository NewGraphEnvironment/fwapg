-- The timing tables and the cell matrix (#34). Run once by `bench.sh setup`,
-- after 00_origins.sql. bench.sh reads fwapg.bench_cells; each timed statement
-- inserts into fwapg.bench_out (unlogged, emptied per repeat) and the run
-- appends a row to fwapg.bench_timings.
--
-- An origin set is (grp, rnk between lo and hi) of fwapg.bench_origins: the
-- random sample's ranks nest, so 1..1000 contains 1..100. A per_origin cell
-- times each origin of its set as its own statement (the single-origin cell).
-- A budget cell runs once, with no warm-up: it is expected to time out and is
-- projected from the cell below it.

-- The sink is pre-extended once and emptied with DELETE and VACUUM between
-- repeats, never TRUNCATE: on this machine the database files sit on a Docker
-- Desktop host mount, where extending a relation costs about 3.7 us a row
-- (1.2 M rows: 4.4 s into new pages, 0.2 s into pages kept by VACUUM). That cost
-- is the mount's, not the method's, and would dominate every large cell.
-- vacuum_truncate = false keeps the emptied pages; 200 M rows covers the
-- largest cell (L2 at 100,000 origins, about 1,774 rows an origin).
DROP TABLE IF EXISTS fwapg.bench_out;

CREATE UNLOGGED TABLE fwapg.bench_out (
  origin_id integer,
  linear_feature_id bigint,
  ord integer,
  cum_m double precision
) WITH (vacuum_truncate = false, autovacuum_enabled = false);

INSERT INTO fwapg.bench_out SELECT g, g, g, g FROM generate_series(1, 200000000) g;
DELETE FROM fwapg.bench_out;
VACUUM fwapg.bench_out;

SELECT 'bench_out pre-extended', pg_size_pretty(pg_relation_size('fwapg.bench_out'));

CREATE TABLE IF NOT EXISTS fwapg.bench_timings (
  id serial PRIMARY KEY,
  at timestamptz NOT NULL DEFAULT now(),
  method text NOT NULL,
  walk text NOT NULL,
  cell text NOT NULL,
  settings text NOT NULL,
  origin_rank integer,          -- per-origin cells only
  rep integer NOT NULL,         -- 0 is the warm-up
  ms double precision,          -- null on timeout or error
  rows bigint,
  note text
);

DROP TABLE IF EXISTS fwapg.bench_cells;

CREATE TABLE fwapg.bench_cells (
  run_order integer PRIMARY KEY,
  method text NOT NULL,
  walk text NOT NULL,
  cell text NOT NULL,
  grp text NOT NULL,
  lo integer NOT NULL,
  hi integer NOT NULL,
  repeats integer NOT NULL,
  warm boolean NOT NULL,
  per_origin boolean NOT NULL,
  budget boolean NOT NULL,
  UNIQUE (method, walk, cell)
);

INSERT INTO fwapg.bench_cells
SELECT row_number() OVER (ORDER BY c.k, m.k, w.k), m.method, w.walk, c.cell, c.grp, c.lo, c.hi,
  CASE
    WHEN m.method = 'L1' AND c.cell = '1000' THEN 1
    WHEN m.method = 'L2' AND c.budget THEN 1
    ELSE 3
  END,
  NOT ((m.method = 'L1' AND c.cell = '1000') OR (m.method = 'L2' AND c.budget)),
  c.cell = '1',
  m.method = 'L2' AND c.budget
FROM (VALUES
  (1, '1', 'random', 1, 20, false),
  (2, '100', 'random', 1, 100, false),
  (3, '1000', 'random', 1, 1000, false),
  (4, '10000', 'random', 1, 10000, false),
  (5, '100000', 'random', 1, 100000, true),
  (6, 'ADMS_1000', 'ADMS', 1, 1000, false),
  (7, 'BULK_1000', 'BULK', 1, 1000, false),
  (8, 'LFRA_1000', 'LFRA', 1, 1000, false),
  (9, 'ADMS', 'ADMS', 1, 2147483647, true),
  (10, 'BULK', 'BULK', 1, 2147483647, true),
  (11, 'LFRA', 'LFRA', 1, 2147483647, true)
) AS c(k, cell, grp, lo, hi, budget)
CROSS JOIN (VALUES (1, 'L1'), (2, 'L2'), (3, 'A-pred'), (4, 'A'), (5, 'P')) AS m(k, method)
CROSS JOIN (VALUES (1, 'full'), (2, '1km')) AS w(k, walk)
WHERE
  -- ltree and the array predicate have no bound: to the outlet only
  (w.walk = 'full' OR m.method IN ('A', 'P'))
  -- the whole groups: to the outlet only
  AND (w.walk = 'full' OR c.cell NOT IN ('ADMS', 'BULK', 'LFRA'))
  AND CASE m.method
    WHEN 'L1' THEN c.cell IN ('1', '100', '1000')
    WHEN 'A-pred' THEN c.cell IN ('1', '1000')
    WHEN 'L2' THEN c.cell != '100'
    ELSE c.cell != '100'
  END;

SELECT run_order, method, walk, cell, repeats, warm, per_origin, budget
FROM fwapg.bench_cells
ORDER BY run_order;
