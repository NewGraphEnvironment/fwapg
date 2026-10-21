-- ltree walks (#34), included by a bench.sh cell or 07_compare.sql with psql
-- variables: method (L1 or L2), grp, lo, hi (the origin set), out (the table the
-- rows go to). The INSERT must stay the file's last statement: the caller reads
-- :ERROR and :ROW_COUNT after it.
--
-- L1: the shipped trace, one call per origin. It reads whse_basemapping.fwa_streams
--     and returns every column with geometry; only the ids and its own order are kept.
-- L2: the ltree predicate the trace is built on, as a join against
--     fwa_stream_networks_sp, ids only, in the trace's order (codes, then measure).
-- Neither has a distance bound: both walk to the outlet.

-- :explain prefixes the INSERT with EXPLAIN (05_explain.sql); empty otherwise
\if :{?explain}
\else
\set explain ''
\endif

SELECT :'method' = 'L1' AS is_l1 \gset

\if :is_l1
:explain INSERT INTO :out (origin_id, linear_feature_id, ord)
SELECT o.origin_id, t.linear_feature_id, t.ordinality
FROM fwapg.bench_origins o
CROSS JOIN LATERAL whse_basemapping.fwa_downstreamtrace(o.blue_line_key, o.measure) WITH ORDINALITY AS t
WHERE o.grp = :'grp' AND o.rnk BETWEEN :lo AND :hi;
\else
:explain INSERT INTO :out (origin_id, linear_feature_id, ord)
SELECT
  o.origin_id,
  s.linear_feature_id,
  row_number() OVER (
    PARTITION BY o.origin_id
    ORDER BY s.wscode_ltree DESC, s.localcode_ltree DESC, s.downstream_route_measure DESC
  )
FROM fwapg.bench_origins o
INNER JOIN whse_basemapping.fwa_stream_networks_sp s
  ON whse_basemapping.fwa_downstream(
    o.blue_line_key, o.measure, o.wscode_ltree, o.localcode_ltree,
    s.blue_line_key, s.downstream_route_measure, s.wscode_ltree, s.localcode_ltree
  )
WHERE o.grp = :'grp' AND o.rnk BETWEEN :lo AND :hi;
\endif
