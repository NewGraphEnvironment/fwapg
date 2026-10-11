-- PCIC outlets placed on FWA streams (extras/pcic_crosswalk, NewGraph fork only),
-- loaded from the export cached in NewGraph's fresh-bc bucket.
-- The table is created here because db/schema.sql does not define it; columns and
-- indexes match the job's table (extras/pcic_crosswalk/sql/pcic_crosswalk04_select.sql and 06_subbasins.sql),
-- with index names as Postgres gives the job's, so loading over a job-built table adds none.
-- One transaction, so a failed download leaves the table as it was.
BEGIN;

  CREATE TABLE IF NOT EXISTS whse_basemapping.pcic_fwa_crosswalk (
    subid integer PRIMARY KEY,
    dowsubid integer,
    anchor_subid integer,          -- nearest placed outlet downstream in PCIC's tree (NULL for a root)
    fwa_parent_subid integer,      -- nearest placed outlet downstream on the FWA
    islake boolean,
    depth integer,
    linear_feature_id bigint,
    blue_line_key integer,
    downstream_route_measure double precision,
    wscode_ltree ltree,
    localcode_ltree ltree,
    watershed_group_code text,
    distance_to_stream double precision,
    candidate_rank integer,
    flag text                      -- NULL, 'no_candidate', 'no_series', 'broken_chain', 'demoted'
  );

  TRUNCATE whse_basemapping.pcic_fwa_crosswalk;

  \copy whse_basemapping.pcic_fwa_crosswalk FROM PROGRAM 'curl -sSf https://fresh-bc.s3.us-west-2.amazonaws.com/fwapg/extras/pcic_fwa_crosswalk.csv.gz | gunzip' delimiter ',' csv header

  CREATE INDEX IF NOT EXISTS pcic_fwa_crosswalk_anchor_subid_idx ON whse_basemapping.pcic_fwa_crosswalk (anchor_subid);
  CREATE INDEX IF NOT EXISTS pcic_fwa_crosswalk_fwa_parent_idx ON whse_basemapping.pcic_fwa_crosswalk (fwa_parent_subid);
  CREATE INDEX IF NOT EXISTS pcic_fwa_crosswalk_linear_feature_id_idx ON whse_basemapping.pcic_fwa_crosswalk (linear_feature_id);
  CREATE INDEX IF NOT EXISTS pcic_fwa_crosswalk_blk_idx ON whse_basemapping.pcic_fwa_crosswalk (blue_line_key, downstream_route_measure);
  CREATE INDEX IF NOT EXISTS pcic_fwa_crosswalk_wscode_ltree_idx ON whse_basemapping.pcic_fwa_crosswalk USING gist (wscode_ltree);
  CREATE INDEX IF NOT EXISTS pcic_fwa_crosswalk_wscode_ltree_idx1 ON whse_basemapping.pcic_fwa_crosswalk USING btree (wscode_ltree);

COMMIT;

ANALYZE whse_basemapping.pcic_fwa_crosswalk;
