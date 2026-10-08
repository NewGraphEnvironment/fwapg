# Task: PCIC routed streamflow on FWA streams: crosswalk hydromosaic outlets, monthly flow per segment (#5)

`extras/discharge` builds `mad_m3s` from PCIC's gridded VIC-GL runoff: annual only, three basins, sampled at watershed centroids, accumulated without routing. PCIC now publishes daily routed streamflow, water temperature and DO-saturation series per sub-basin outlet through a public API (`beehive.pacificclimate.org/hydromosaic`). They cover most of BC, on PCIC's own network (`subid` / `dowsubid`), with no FWA key.

Branch off `newgraph`; PR targets `newgraph`.


## Phase 1: Fetch PCIC network and series
- [ ] `extras/pcic_crosswalk/pcic_crosswalk.sh` skeleton in the `discharge.sh` shape; base URL `https://beehive.pacificclimate.org` held in one variable
- [ ] Page through `bbox-server/collections/rivers/items.json` (limit 1000) into `data/rivers/*.geojson`, cached so re-runs skip pages already fetched; load to `fwapg.pcic_rivers` with `ogr2ogr` (`subid`, `dowsubid`, `islake`, geom, EPSG:3005)
- [ ] Derive the outlet point = downstream end of each segment; check the direction against `dowsubid` adjacency (the outlet should touch the downstream segment) and record how many don't match
- [ ] For each `subid`, read the timeseries list and keep the PNWNAmet `streamflow` id; fetch its CSV into `data/series/<subid>.csv`. Cached and resumable, with modest parallelism (`parallel --jobs 4`) and retry on failure
- [ ] Reduce to monthly climatology in the shell/SQL load step: mean of daily values per calendar month, 1951–2012 → `fwapg.pcic_outlet_monthly (subid, month, q_m3s)`

## Phase 2: Snap outlets to the FWA
- [ ] `sql/pcic_crosswalk01_candidates.sql`: `LATERAL FWA_IndexPoint(outlet_geom, <tol>, <n>)` per WSG, joined to `fwa_stream_networks_sp` for `edge_type`, dropping 1425 → `fwapg.pcic_candidates`
- [ ] `sql/pcic_crosswalk02_select.sql`: rank each outlet's candidates by distance, then keep the closest one whose position has its `dowsubid` outlet's chosen position downstream (`FWA_Downstream`, measure-aware). Resolve from the outlets (no upstream PCIC sub-basin) downward, or iterate to a fixed point
- [ ] Write `whse_basemapping.pcic_fwa_crosswalk (subid, dowsubid, linear_feature_id, blue_line_key, downstream_route_measure, wscode_ltree, localcode_ltree, distance_to_stream, candidate_rank, flag)`; `flag` marks no valid candidate, broken chain or lake outlet

## Phase 3: Monthly flow per FWA segment
- [ ] Local inflow per sub-basin per month = `Q_out − Σ Q_in` over direct upstream outlets (clamped at ≥ 0, with clamped counts reported)
- [ ] Local FWA area per sub-basin = upstream area at the outlet's FWA position minus the area upstream of its direct upstream outlets' positions (from `fwa_watersheds_upstream_area` + `fwa_streams_watersheds_lut`)
- [ ] `sql/pcic_crosswalk03_segments.sql`, per WSG: for each FWA segment assigned to a sub-basin (downstream of the upstream outlets, upstream of or at this outlet), `q = Σ Q_out(upstream PCIC outlets above the segment) + local_inflow × (local FWA area upstream of segment / sub-basin local FWA area)`
- [ ] Output `whse_basemapping.fwa_stream_networks_discharge_monthly (linear_feature_id, watershed_group_code, month, q_m3s)`, PK `(linear_feature_id, month)`; tables are created by the job, not added to `db/schema.sql`
- [ ] `\copy` both outputs to `.csv.gz`; drop the `fwapg.pcic_*` staging tables

## Phase 4: QA and docs
- [ ] `extras/pcic_crosswalk/sql/qa.sql` in the `result = t` style: every non-flagged outlet's segment `q` ≈ PCIC `Q_out` (mass balance), monthly `q` is non-decreasing downstream along a sample mainstem, flagged share under a stated threshold
- [ ] Gauge check: Bulkley River near Houston (08EE003) monthly means vs the segment's `q` (the recipe is in `knowledge/research/modelled_discharge.md`)
- [ ] Report snap-distance distribution, flagged counts by reason, and coverage by WSG
- [ ] `extras/pcic_crosswalk/README.md`: purpose, requirements (`jq`, `ogr2ogr`, `parallel`), run, output tables, caveats (BasinMaker network ≠ FWA, sub-basins resolve about 5× finer than VIC-GL, no Liard), and a Data Citation crediting PCIC hydromosaic (PNWNAmet run)
- [ ] Add the two output files to the `extras/README.md` upload list (the upload itself isn't run)

## Validation
- [ ] Tests pass (`psql $DATABASE_URL -f extras/pcic_crosswalk/sql/qa.sql`, all `t`)
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

## Out of scope
- Water temperature and DO-saturation (same pipeline later; the issue says "can come the same way")
- CMIP6 future runs, `load.sh` integration, and any change to existing fwapg functions or `db/schema.sql`
- Offering the work upstream

