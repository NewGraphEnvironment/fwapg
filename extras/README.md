# Extras

Value added FWA data that generally requires several hours to generate. 
Rather than re-generate the lookups each time the database is loaded, `fwapg` loads this data from files cached to nrs.objectstore.

## Updates 

Updates to the lookups are generally required whenever the source FWA geometries and codes have changed.
Update source FWA files in your database, then regenerate the cached data files using scripts in this folder.
When complete, upload to nrs.objectstore:

	aws s3 cp channel_width/fwa_stream_networks_channel_width.csv.gz s3://bchamp/fwapg/fwa_stream_networks_channel_width.csv.gz --acl public-read
	aws s3 cp discharge/fwa_stream_networks_discharge.csv.gz s3://bchamp/fwapg/fwa_stream_networks_discharge.csv.gz --acl public-read
	aws s3 cp precipitation/fwa_stream_networks_mean_annual_precip.csv.gz s3://bchamp/fwapg/fwa_stream_networks_mean_annual_precip.csv.gz --acl public-read
	aws s3 cp lookups/fwa_assessment_watersheds_lut.csv.gz s3://bchamp/fwapg/fwa_assessment_watersheds_lut.csv.gz --acl public-read
	aws s3 cp lookups/fwa_assessment_watersheds_streams_lut.csv.gz s3://bchamp/fwapg/fwa_assessment_watersheds_streams_lut.csv.gz --acl public-read
	aws s3 cp lookups/fwa_waterbodies_upstream_area.csv.gz s3://bchamp/fwapg/fwa_waterbodies_upstream_area.csv.gz --acl public-read
	aws s3 cp lookups/fwa_watersheds_upstream_area.csv.gz s3://bchamp/fwapg/fwa_watersheds_upstream_area.csv.gz --acl public-read

Note that no metadata is currently provided to link versions of these add-ons to a given version of the FWA data (this is a to-do).

The PCIC crosswalk outputs (`pcic_crosswalk/`, NewGraph fork only) go to NewGraph's `fresh-bc` bucket rather than `bchamp`,
under `fwapg/extras/`, the one `fwapg/` prefix that is public-read (the rest of `fwapg/` is private). `load.sh` loads them from there.
A run writes `pcic.<table>.csv.gz` for the tables every run shares, and `pcic.<table>.<run>.csv.gz` for its own rows
(`pcic_crosswalk/README.md`). Upload only after the job has printed `PCIC crosswalk complete`, and upload the shared
files with every run, since `pcic.runs` lists them all. A `DAYS=1` run also writes one parquet file per year of the
model's series to `data/days/<model>_<scenario>/`, listed in `pcic.series`. Upload those first, flat beside the other
files, and the `.csv.gz` files after them, so that the catalogue never describes files that are not there yet:

	(cd pcic_crosswalk && for f in data/days/*/pcic.subbasin_days.*.parquet; do aws s3 cp "$f" "s3://fresh-bc/fwapg/extras/$(basename "$f")"; done)
	(cd pcic_crosswalk && for f in pcic.*.csv.gz; do aws s3 cp "$f" "s3://fresh-bc/fwapg/extras/$f"; done)

`fwa_stream_networks_discharge_monthly.csv.gz` and `pcic_fwa_crosswalk.csv.gz` there are the first build, loaded into
`whse_basemapping` until their readers move to `pcic`; the job no longer writes them.

The main-flow tree (`mainflow_tree/`, NewGraph fork only) goes there too (`load.sh` does not load it yet):

	aws s3 cp mainflow_tree/fwa_stream_networks_mainflow_tree.csv.gz s3://fresh-bc/fwapg/extras/fwa_stream_networks_mainflow_tree.csv.gz
