-- PCIC monthly flow per FWA stream segment (extras/pcic_crosswalk, NewGraph fork only),
-- loaded from the export cached in NewGraph's fresh-bc bucket.
-- The table is created here because db/schema.sql does not define it; columns match
-- the job's table (extras/pcic_crosswalk/pcic_crosswalk.sh).
-- One transaction, so a failed download leaves the table as it was.
BEGIN;

  CREATE TABLE IF NOT EXISTS whse_basemapping.fwa_stream_networks_discharge_monthly (
    linear_feature_id bigint,
    watershed_group_code text,
    month integer,
    q_m3s double precision,
    PRIMARY KEY (linear_feature_id, month)
  );

  TRUNCATE whse_basemapping.fwa_stream_networks_discharge_monthly;

  \copy whse_basemapping.fwa_stream_networks_discharge_monthly FROM PROGRAM 'curl -sSf https://fresh-bc.s3.us-west-2.amazonaws.com/fwapg/extras/fwa_stream_networks_discharge_monthly.csv.gz | gunzip' delimiter ',' csv header

COMMIT;

ANALYZE whse_basemapping.fwa_stream_networks_discharge_monthly;
