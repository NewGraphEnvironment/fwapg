BEGIN;

-- Break exact distance ties in FWA_IndexPoint so the result no longer depends on
-- row order. A point nearest the vertex two segments of one stream share is
-- equally far from both, and DISTINCT ON (blue_line_key) ... ORDER BY
-- blue_line_key, distance_to_stream returned whichever row the plan reached
-- first. When that was the segment below the vertex, the measure returned
-- (its downstream_route_measure + length_metre) could fall short of the next
-- segment's start, and FWA_LocateAlong returned no point for it.
--
-- The tie now goes to the segment starting at the vertex: measures run
-- [downstream, upstream), so it is the segment a measure there falls on, and the
-- measure returned is its downstream_route_measure. A tie between segments that
-- do not share a vertex (a meander) also goes to the upper one, which is only a
-- fixed choice. The outer ORDER BY now sorts on the unrounded distance and breaks
-- ties on linear_feature_id.

CREATE OR REPLACE FUNCTION whse_basemapping.fwa_indexpoint(point public.geometry, tolerance double precision DEFAULT 5000, num_features integer DEFAULT 1) RETURNS TABLE(linear_feature_id bigint, gnis_name text, wscode_ltree public.ltree, localcode_ltree public.ltree, blue_line_key integer, downstream_route_measure double precision, distance_to_stream double precision, bc_ind boolean, geom public.geometry)
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $_$

WITH pt AS

(
    SELECT
      p.geom,
      CASE
        WHEN wsg.watershed_group_code is NULL THEN False
        ELSE True
      END as bc_ind
    FROM
    (
        SELECT $1 as geom
    ) p
    LEFT OUTER JOIN whse_basemapping.fwa_watershed_groups_poly wsg
    ON ST_intersects(p.geom, wsg.geom)
)

SELECT
    linear_feature_id,
    gnis_name,
    wscode_ltree,
    localcode_ltree,
    blue_line_key,
    (ST_LineLocatePoint(stream_geom,
      ST_ClosestPoint(stream_geom, pt_geom))
      * length_metre
    ) + downstream_route_measure AS downstream_route_measure,
    ROUND(distance_to_stream::numeric, 3) AS distance_to_stream,
    bc_ind,
    ST_ClosestPoint(stream_geom, pt_geom) as geom
FROM
(
    SELECT DISTINCT ON (blue_line_key)
        linear_feature_id,
        gnis_name,
        wscode_ltree,
        localcode_ltree,
        blue_line_key,
        length_metre,
        downstream_route_measure,
        stream_geom,
        pt_geom,
        bc_ind,
        distance_to_stream
    FROM
        (
            SELECT
                linear_feature_id,
                gnis_name,
                wscode_ltree,
                localcode_ltree,
                blue_line_key,
                length_metre,
                downstream_route_measure,
                ST_LineMerge(str.geom) as stream_geom,
                pt.geom as pt_geom,
                ST_Distance(str.geom, pt.geom) as distance_to_stream,
                pt.bc_ind
            FROM whse_basemapping.fwa_stream_networks_sp AS str,
            pt
            -- do not use 6010 lines, only return nearest stream inside BC
            WHERE edge_type != 6010
            ORDER BY str.geom <-> (select geom from pt)
            LIMIT 100
        ) AS f
    -- a point nearest the vertex two segments share is equally near both: take
    -- the one starting there, the segment its measure falls on
    ORDER BY blue_line_key, distance_to_stream, downstream_route_measure DESC, linear_feature_id
) b
WHERE distance_to_stream <= $2
-- b. is the unrounded distance; the bare name is the rounded output column
ORDER BY b.distance_to_stream asc, linear_feature_id
LIMIT $3

$_$;

COMMIT;
