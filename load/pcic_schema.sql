-- The pcic schema: PCIC hydromosaic routed flow placed on FWA streams
-- (extras/pcic_crosswalk, NewGraph fork only), kept out of whse_basemapping because
-- it is derived and rebuilt (NewGraphEnvironment/fwapg#23).
--
-- Shared by every run: the placed outlets (fwa_crosswalk), each segment's flow
-- weights (segment_weights) and the calendar-day week bins (day_bins). Per run,
-- keyed by model, scenario and period: sub-basin flow per calendar day
-- (subbasin_daily) and segment flow per month and week (discharge_monthly,
-- discharge_weekly). runs lists the runs with each table's fingerprint. Per model
-- and scenario, series lists the per-year sub-basin days published as parquet
-- (one file a year, never loaded here), with each file's fingerprint.
--
-- Run by pcic_crosswalk.sh before its export and by load.sh before its loads;
-- creates only what is missing.

CREATE SCHEMA IF NOT EXISTS pcic;

CREATE TABLE IF NOT EXISTS pcic.runs (
  model text,
  scenario text,
  period text,                   -- years averaged, first-last
  crosswalk_md5 text,            -- md5 of the crosswalk the run was built on (one per database)
  weights_rows bigint,
  weights_share_sum numeric,     -- sum(round(share::numeric, 9))
  daily_rows bigint,
  daily_subbasins bigint,
  daily_q_sum numeric,           -- sum(round(q_acc::numeric, 6))
  monthly_rows bigint,
  monthly_segments bigint,
  monthly_q_sum numeric,         -- sum(round(q_m3s::numeric, 6))
  weekly_rows bigint,            -- NULL where the run has no weekly flow
  weekly_segments bigint,
  weekly_q_sum numeric,
  built_at timestamptz,
  PRIMARY KEY (model, scenario, period)
);

CREATE TABLE IF NOT EXISTS pcic.day_bins (
  month integer,
  day integer,
  week integer,                  -- week 1 = Jan 1-7, ..., week 52 = Dec 24-31; Feb 29 in week 9
  PRIMARY KEY (month, day)
);

CREATE TABLE IF NOT EXISTS pcic.fwa_crosswalk (
  subid integer PRIMARY KEY,
  dowsubid integer,
  anchor_subid integer,          -- nearest placed outlet downstream in PCIC's tree (NULL for a root)
  fwa_parent_subid integer,      -- nearest placed outlet downstream on the FWA, or a diversion's PCIC ancestor
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
CREATE INDEX IF NOT EXISTS fwa_crosswalk_anchor_subid_idx ON pcic.fwa_crosswalk (anchor_subid);
CREATE INDEX IF NOT EXISTS fwa_crosswalk_fwa_parent_subid_idx ON pcic.fwa_crosswalk (fwa_parent_subid);
CREATE INDEX IF NOT EXISTS fwa_crosswalk_linear_feature_id_idx ON pcic.fwa_crosswalk (linear_feature_id);
CREATE INDEX IF NOT EXISTS fwa_crosswalk_blk_idx ON pcic.fwa_crosswalk (blue_line_key, downstream_route_measure);

-- q = greatest(sum(q_acc of upstream_subids) + q_local(subid) * share, 0), from
-- the sub-basin flows of any period (README)
CREATE TABLE IF NOT EXISTS pcic.segment_weights (
  linear_feature_id bigint PRIMARY KEY,
  watershed_group_code text,
  subid integer,                 -- the segment's sub-basin: nearest placed outlet on or below it
  share double precision,        -- share of the sub-basin's local flow that passes the segment
  upstream_subids integer[]      -- placed outlets directly above the sub-basin whose water passes the segment
);
CREATE INDEX IF NOT EXISTS segment_weights_watershed_group_code_idx ON pcic.segment_weights (watershed_group_code);
CREATE INDEX IF NOT EXISTS segment_weights_subid_idx ON pcic.segment_weights (subid);

CREATE TABLE IF NOT EXISTS pcic.subbasin_daily (
  model text,
  scenario text,
  period text,
  subid integer,
  month integer,
  day integer,
  n_days integer,                -- days of the period on this calendar day: the weight when averaging days
  q_local double precision,      -- flow generated in the sub-basin (can be negative)
  q_acc double precision,        -- flow accumulated at the sub-basin's outlet
  PRIMARY KEY (model, scenario, period, subid, month, day)
);

CREATE TABLE IF NOT EXISTS pcic.discharge_monthly (
  model text,
  scenario text,
  period text,
  linear_feature_id bigint,
  watershed_group_code text,
  month integer,
  q_m3s double precision,
  PRIMARY KEY (model, scenario, period, linear_feature_id, month)
);

CREATE TABLE IF NOT EXISTS pcic.discharge_weekly (
  model text,
  scenario text,
  period text,
  linear_feature_id bigint,
  watershed_group_code text,
  week integer,
  q_m3s double precision,
  PRIMARY KEY (model, scenario, period, linear_feature_id, week)
);

-- one row per year of a model and scenario's per-year sub-basin days, the file
-- pcic.subbasin_days.<model>_<scenario>.<year>.parquet (subid, date, q_local,
-- q_acc; extras/pcic_crosswalk/README.md). A sum is sum(floor(double(v) * 1000 +
-- 0.5)) over the file's float32 values v, which every reader reproduces exactly.
CREATE TABLE IF NOT EXISTS pcic.series (
  model text,
  scenario text,
  year integer,
  crosswalk_md5 text,            -- md5 of the crosswalk the days were built on, as in pcic.runs
  rows bigint,                   -- rows in the file: subbasins x days of the year
  subbasins bigint,
  q_local_sum bigint,
  q_acc_sum bigint,
  bytes bigint,                  -- the file's size
  commit text,                   -- the fwapg commit that built the file
  built_at timestamptz,
  PRIMARY KEY (model, scenario, year)
);
