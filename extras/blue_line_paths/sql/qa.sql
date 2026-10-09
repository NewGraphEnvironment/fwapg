-- QA tests for the blue line paths, all should return result = t.
-- blue_line_paths.sh stops if any is f.

-- A stream that reaches its parent
-- outside BC has none, and a stream that reaches its parent through a braid does.
-- Projecting mouths onto parents they never touch put the Okanagan on the
-- Columbia in BC; requiring a side channel to touch its own main stem left the
-- Kitsumkalum (which enters the Skeena through a braid) without a path.
SELECT 'the Okanagan, which leaves BC, has no path' AS test,
  EXISTS (SELECT 1 FROM fwapg.blk_paths)
  AND NOT EXISTS (SELECT 1 FROM fwapg.blk_paths WHERE blue_line_key = 356570548) AS result;

SELECT 'the Kitsumkalum, which joins the Skeena through a braid, has a path to the Skeena' AS test,
  EXISTS (
    SELECT 1 FROM fwapg.blk_paths
    WHERE blue_line_key = 360883243 AND 360887278 = ANY(path_blks)
  ) AS result;

SELECT 'Cayoosh Creek, which joins the Seton through a side channel that touches nothing, has a path to the Fraser' AS test,
  EXISTS (
    SELECT 1 FROM fwapg.blk_paths
    WHERE blue_line_key = 356364387 AND 356364114 = ANY(path_blks)
  ) AS result;
