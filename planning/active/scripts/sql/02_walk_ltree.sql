-- ltree walks (#34), included by a bench.sh cell, 05_explain.sql, 07_results.sql
-- or 07_compare.sql with psql variables method (L1 or L2), grp, lo, hi (the
-- origin set) and the sink below. The walk must stay the file's last statement:
-- a cell reads :ERROR after it.
--
-- L1: the shipped trace, one call per origin. It reads whse_basemapping.fwa_streams
--     and returns every column with geometry; only the ids and its own order are kept.
-- L2: the ltree predicate the trace is built on, as a join against
--     fwa_stream_networks_sp, ids only, in the trace's order (codes, then measure).
-- Neither has a distance bound: both walk to the outlet, and cum_m is null.
--
-- How the rows are consumed: the walk's SELECT, which returns (origin_id,
-- linear_feature_id, ord, cum_m), is wrapped in :sink_open ... :sink_close and
-- ended with \gset when :sink_gset is true, ; otherwise.
--   timing cell (bench.sh): one row of aggregates over every column, so every
--     row is computed and none is written (PostgreSQL never runs a data-modifying
--     statement in parallel, and writing new pages is slow on this host mount);
--     :n is the row count.
--   results (07_results.sql, 07_compare.sql): INSERT INTO :out, the default.
-- :explain prefixes the statement with EXPLAIN (05_explain.sql).
\if :{?explain}
\else
\set explain ''
\endif
\if :{?sink_open}
\else
\set sink_open 'INSERT INTO ' :out ' (origin_id, linear_feature_id, ord, cum_m)'
\set sink_close ''
\set sink_gset false
\endif

SELECT :'method' = 'L1' AS is_l1 \gset

\if :is_l1
:explain :sink_open
SELECT o.origin_id, t.linear_feature_id, t.ordinality::integer AS ord, NULL::double precision AS cum_m
FROM fwapg.bench_origins o
CROSS JOIN LATERAL whse_basemapping.fwa_downstreamtrace(o.blue_line_key, o.measure) WITH ORDINALITY AS t
WHERE o.grp = :'grp' AND o.rnk BETWEEN :lo AND :hi
:sink_close
\if :sink_gset
\gset
\else
;
\endif
\else
:explain :sink_open
SELECT
  o.origin_id,
  s.linear_feature_id,
  row_number() OVER (
    PARTITION BY o.origin_id
    ORDER BY s.wscode_ltree DESC, s.localcode_ltree DESC, s.downstream_route_measure DESC
  )::integer AS ord,
  NULL::double precision AS cum_m
FROM fwapg.bench_origins o
INNER JOIN whse_basemapping.fwa_stream_networks_sp s
  ON whse_basemapping.fwa_downstream(
    o.blue_line_key, o.measure, o.wscode_ltree, o.localcode_ltree,
    s.blue_line_key, s.downstream_route_measure, s.wscode_ltree, s.localcode_ltree
  )
WHERE o.grp = :'grp' AND o.rnk BETWEEN :lo AND :hi
:sink_close
\if :sink_gset
\gset
\else
;
\endif
\endif
