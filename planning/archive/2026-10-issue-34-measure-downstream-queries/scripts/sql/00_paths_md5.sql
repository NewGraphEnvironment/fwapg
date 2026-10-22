-- Sorted-row md5 of the blue line path tables, before and after the re-timed
-- build (bench.sh paths). Floats print in their shortest exact form, so equal
-- md5s mean equal values.

SELECT 'blk_parents', count(*), md5(string_agg(t::text, E'\n' ORDER BY t.blue_line_key))
FROM fwapg.blk_parents t;

SELECT 'blk_paths', count(*), md5(string_agg(t::text, E'\n' ORDER BY t.blue_line_key))
FROM fwapg.blk_paths t;
