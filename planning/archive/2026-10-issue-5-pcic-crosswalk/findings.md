# Findings — PCIC routed streamflow on FWA streams (#5)

## Issue context

**If we do it:** FWA streams get monthly flow from PCIC's routed Raven/VIC-GL model for most of BC, not only the Fraser, Peace and Columbia that `fwa_stream_networks_discharge` covers. Water temperature can come the same way. **If we never do:** modelled flow on the FWA stays annual-only and limited to three basins.

## Problem
`extras/discharge` builds `mad_m3s` from PCIC's gridded VIC-GL runoff: annual only, three basins, sampled at watershed centroids, accumulated without routing. PCIC now publishes daily routed streamflow, water temperature and DO-saturation series per sub-basin outlet through a public API (`beehive.pacificclimate.org/hydromosaic`). They cover most of BC, on PCIC's own network (`subid` / `dowsubid`), with no FWA key.

## Proposed solution
A new `extras/pcic_crosswalk/` job, in the shape of `extras/discharge`:
- [ ] Pull outlet points (`bbox-server/collections/upstreams`) and the observed-weather (PNWNAmet) streamflow series.
- [ ] Batch-snap the outlets with a `LATERAL` join on `fwa_indexpoint(..., num_features)`, skipping edge type 1425.
- [ ] Pick the candidate that keeps PCIC's chain intact: each outlet's `dowsubid` must be downstream on the FWA (`FWA_Downstream`). Flag outlets with no valid candidate.
- [ ] Per FWA segment, monthly climatology = flow from upstream PCIC outlets + its sub-basin's own runoff × the share of that sub-basin's area upstream of the segment.
- [ ] Output `fwa_stream_networks_discharge_monthly` (`linear_feature_id`, month, `q_m3s`), plus the crosswalk table.
- [ ] Data source: PCIC, cited as such.

No changes to existing fwapg functions. Not yet offered upstream.

## Plan-mode exploration (2026-10-07)


- **The API paths in the issue are wrong.** `bbox-server` sits at the host root, not under `/hydromosaic` (verified today, and matching `knowledge/research/modelled_discharge.md`):
  - `GET /bbox-server/collections/rivers/items.json?limit=1000&offset=N` returns 48,261 river segments as MultiLineStrings in BC Albers. Feature `id` = `subid`, with properties `dowsubid`, `islake` and `uid`. One page of 1,000 is about 3 MB and takes about 1.3 s. **This is the bulk source for outlets.** `upstreams` is per-id (`upstream_subids`), so it doesn't work for bulk pulls.
  - `GET /hydromosaic/outlets/{subid}/timeseries` lists 51 series (model, scenario, variable). PNWNAmet streamflow is the run driven by observed weather. `GET .../timeseries/{id}/data` returns a CSV with a short header. Day 1 is a start-up artefact, so 1950 is dropped.
- **PCIC publishes no sub-basin polygons.** The sub-basin's own area has to be defined on the FWA: area upstream of the outlet's FWA position, minus the area upstream of its direct upstream PCIC outlets (`dowsubid = this subid`).
- `whse_basemapping.FWA_IndexPoint(geom, tolerance, num_features)` (`db/schema.sql:2373`) excludes edge 6010 and returns one candidate per `blue_line_key`, but **does not exclude 1425**, so the job filters candidates itself (that needs `edge_type`, joined from `fwa_stream_networks_sp`).
- `FWA_Downstream(blk, drm, wscode, localcode, blk, drm, wscode, localcode)` (`db/schema.sql:2135`) is the measure-aware test for chain validation.
- `fwa_watersheds_upstream_area` and `fwa_streams_watersheds_lut` already give FWA upstream area per watershed and per stream. `discharge03_wsd.sql` shows the per-WSG `parallel` + `FWA_Upstream` pattern and its LWLock caveat (cap at 5 jobs).
- Job shape to copy: `extras/discharge/discharge.sh` (`set -euxo pipefail`, `$PSQL -v ON_ERROR_STOP=1`, `fwapg.*` staging tables, per-WSG `parallel`, `\copy` to `.csv.gz`, drop staging tables), plus a README with a Data Citation section.
- Tests in `tests/` are plain SQL files where every row returns `result = t`. The new job gets a matching `qa.sql`.

