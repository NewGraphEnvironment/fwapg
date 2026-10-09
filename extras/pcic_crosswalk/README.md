## PCIC routed streamflow on FWA streams

The [Pacific Climate Impacts Consortium](https://www.pacificclimate.org) (PCIC) publishes daily streamflow
routed by Raven (driven by VIC-GL runoff) for about 48,700 sub-basin outlets covering the Fraser, Peace,
Columbia, Kettle, Okanagan and BC coast domains (no Liard). It is served through PCIC's hydromosaic API, on
PCIC's own river network (`subid` / `dowsubid`), which shares no key with the FWA.

This job crosswalks PCIC's outlets onto FWA streams and derives a monthly flow climatology for every FWA
stream segment below or within PCIC's network. Unlike `extras/discharge` (annual, three basins, unrouted
gridded runoff accumulated on the FWA), flow here is PCIC's routed flow at placed outlets wherever PCIC's
network and the FWA agree, with only the flow generated between outlets distributed by FWA drainage area.


## Requirements

- `curl`, `jq`
- `ogr2ogr` (GDAL)
- `cdo` and `ncdump` (netCDF)
- an fwapg database with `fwa_streams_watersheds_lut` and `fwa_watersheds_upstream_area` loaded


## Processing

    ./pcic_crosswalk.sh

The job:

1. **Network.** Pages PCIC's `rivers` and `lakes` collections from `bbox-server` (BC Albers) into
   `data/`, and loads them. Each river segment's outlet is the end that touches its downstream feature
   (`dowsubid`); segments carry no direction otherwise. A lake's outlet is the upstream end of the river
   that drains it.
2. **Series.** Downloads the PNWNAmet (observed weather) streamflow run for every outlet through the
   hydromosaic bulk endpoint (NetCDF, 500 outlets per request, one domain per request; batches are halved
   on a mixed-domain 422, or on repeated failure while above 50 outlets) and reduces each batch to a
   1951-2012 monthly mean with `cdo` (1950 is dropped: day 1 of the run is a start-up artefact).
   Downloads are cached and resumable; outlets with no series are listed in `data/series/missing.txt`.
3. **Snapping.** Up to 5 FWA candidates per outlet within 150 m, one per blue line: `FWA_IndexPoint`'s
   search, with unusable segments excluded *before* the nearest segment of each blue line is picked.
   Excluded: subsurface flow edges (`1425`), streams off the network (watershed codes under `999`) or
   with no local code, and segments with no fundamental watershed. (`FWA_IndexPoint` keeps one segment
   per stream and can exclude only `6010`, so filtering its output loses the whole stream when its
   nearest segment is unusable: 651 streams with a usable segment in reach.) A candidate on a side
   channel also gets its main stem (within 1 km) as a candidate, which the outlets above choose between
   in placement: PCIC's network is single-threaded, and a point on a side channel receives only that
   channel's water, but FWA often codes a tributary's last reach as a side channel of the river it joins. Outlets sit at confluences, so the point snapped is
   up to 100 m back up the PCIC segment rather than the junction itself.

   Every position comparison in the job ("is b on or upstream of a?") uses the downstream path of each FWA
   blue line (`fwapg.blk_paths`, built by `extras/blue_line_paths`): the chain of blue lines its water passes to the sea, with the
   measure at which it joins each. A main stem joins the main stem of its parent watershed code at the
   segment whose local code equals its watershed code, unless its mouth enters a side channel of that
   main stem, in which case it joins where the side channel rejoins. Otherwise (and for side channels) a
   line joins the line its mouth touches, within 1 m, including a braid that rejoins its main stem
   through a sibling braid; a side channel that touches nothing joins its own main stem (at the segment
   with its lowest local code, or the nearest point within 1 km). Other lines whose mouths touch nothing
   at or below their own code have no path.
   `FWA_Upstream` is not used: it orders positions by comparing local codes, and local codes nest more than one level deep, run
   out of order along blue lines, and are compared across main and side channels, each of which put
   outlets on the wrong side of tributaries.
4. **Placement.** Outlets are placed from each tree's root upward so that every outlet lies on or upstream
   of the nearest placed outlet below it, keeping PCIC's routing chain intact on the FWA. Among valid
   candidates an outlet takes the one most of the PCIC network above it agrees with (outlets up to three
   levels above whose near candidates lie on or upstream of it), then the nearest. An outlet with no series is not placed (`no_series`). An outlet with no valid candidate is
   left unplaced (`broken_chain`); where the outlet that broke carries most of its parent's network and
   fits once the parent is skipped, the parent is `demoted` instead and placement reruns, until stable.
5. **Flow at outlets.** PCIC's network and the FWA do not always join streams at the same place, so
   PCIC's outflows are not used as they stand. Each PCIC outlet's local runoff (its outflow minus its PCIC
   children's) is given to the sub-basin of the outlet, or of its nearest placed PCIC ancestor if it is
   unplaced, and accumulated down the FWA tree of placed outlets (`fwa_parent_subid`, the nearest placed
   outlet downstream on the FWA). Where the networks agree, the accumulated flow at an outlet is PCIC's
   outflow; where they do not, flow follows the FWA.
6. **Segments.** Each FWA segment belongs to the sub-basin of the nearest placed outlet on or below it.
   Per month,

       q = sum(q_acc of outlets directly above the segment's sub-basin and above the segment)
           + q_local * (A - sum(A of those outlets)) / A_local

   where `q_acc` is accumulated flow, `q_local` the runoff given to the sub-basin, `A` FWA upstream area
   and `A_local` the sub-basin's own FWA area. At the segment an outlet is placed on, `q` is the outlet's
   accumulated flow. Local runoff can be negative in a month (routing losses), so `q` is clamped at zero.
7. **QA and export.** Runs the tests in `sql/qa.sql` and stops, keeping the staging tables, if any fails;
   then prints `sql/qa_report.sql`, writes both output tables to `.csv.gz`, and drops the `fwapg.pcic_*`
   staging tables. The QA tables `fwapg.pcic_qa_drainage` (step 7's drainage check) and
   `fwapg.pcic_qa_gauges` (`qa_gauges.sh`) are kept for review.

To check against every Water Survey of Canada gauge in BC with discharge in the PCIC years (needs the
job's outputs and its `data/` cache; writes `data/qa_gauges.csv`):

    ./qa_gauges.sh

At each gauge it compares PCIC's own flow at the nearest PCIC segment (no crosswalk involved) with
the flow on the FWA segment at the gauge, which isolates crosswalk error from PCIC's model error, and
both with the gauge. In the 2026-10 build, at 538 gauges: FWA flow within 10% of PCIC's at 494
(207 of 210 gauges of 100-1,000 km², 134 of 139 of 1,000-10,000 km²); 11 more where another PCIC
branch at the confluence matches; 33 disagree, 27 of them under 100 km². The FWA stream picked by
drainage area matched the gauge's area within 10% at 559 of 603 gauges. One gauge in detail:

    ./qa_gauge.sh 08EE003

The job's QA step also checks drainage size at every placed outlet (`sql/qa_drainage.sql`, written to
`data/qa_drainage.csv`), which flow agreement cannot: a chain of outlets shifted onto a neighbouring
stream still adds up. PCIC publishes no sub-basin areas, so PCIC's drainage is measured as its upstream
river length and its mean flow, each per FWA km² at the placed segment and normalised by the watershed
group's median (the province's, for groups with fewer than 20 main-stem placements). An outlet is flagged `small` (both < 0.2: a small PCIC outlet on a much bigger FWA
stream) or `big` (both > 5). Side channels are not checked: the watershed lookup gives them their main
river's area. In the 2026-10 build: 218 `small` and 126 `big` of 37,040 main-stem placements, with 82
of the 85 outlets carrying more than 10 times PCIC's flow among the `small`. Seeded errors (the Nicola
main stem on Clapperton Creek; outlets moved onto streams with 10 times, or a tenth of, the area) are
flagged; a wrong stream of similar size (within about 5 times) is not. Flags are a review list
(NewGraphEnvironment/fwapg#8): lake connector lines, double-line river construction lines and regulated
flow (the Cheslatta River) trip it too.


## Output tables

    Table "whse_basemapping.fwa_stream_networks_discharge_monthly"
           Column        |       Type       | Nullable
    ----------------------+------------------+----------
     linear_feature_id    | bigint           | not null
     watershed_group_code | text             |
     month                | integer          | not null
     q_m3s                | double precision |
    Primary key: (linear_feature_id, month)

    Table "whse_basemapping.pcic_fwa_crosswalk"
           Column             |       Type       |
    --------------------------+------------------+--------------------------------------------------
     subid                    | integer          | PCIC outlet id (primary key)
     dowsubid                 | integer          | PCIC downstream outlet
     anchor_subid             | integer          | nearest placed outlet downstream in PCIC's tree
     fwa_parent_subid         | integer          | nearest placed outlet downstream on the FWA
     islake                   | boolean          |
     depth                    | integer          | steps to the root of the PCIC tree
     linear_feature_id        | bigint           | FWA position (NULL if unplaced)
     blue_line_key            | integer          |
     downstream_route_measure | double precision |
     wscode_ltree             | ltree            |
     localcode_ltree          | ltree            |
     watershed_group_code     | text             |
     distance_to_stream       | double precision | snap distance (m)
     candidate_rank           | integer          | 1 = nearest candidate
     flag                     | text             | NULL, no_candidate, no_series, broken_chain, demoted


## Caveats

- PCIC's network is not the FWA; it is probably a BasinMaker product. How it was built, the Raven
  configuration and how runoff cells map to sub-basins are not published.
- Unplaced outlets (outside BC, beyond 150 m of an FWA stream, or inconsistent with the chain) are not
  lost: their runoff goes to the nearest placed outlet below them in PCIC's tree and is spread over that
  sub-basin by area. Flow from outlets outside BC (US, Alberta) is spread over BC area the same way.
- Where PCIC joins a tributary to the mainstem at a different place than the FWA does, flow on the
  stretch between the two junctions differs from PCIC's. `sql/qa_report.sql` counts the outlets where
  the accumulated flow and PCIC's outflow differ by more than 5%.
- Within a sub-basin, flow is distributed by drainage area only. Sub-basins are small (about 5x finer
  than VIC-GL's ~25 km² cells), so small streams usually sit inside one. Where an outlet and the outlets
  above it map to the same fundamental watershed (the lookup can give a tributary mouth the polygon of
  the stream it joins), the sub-basin has no local area of its own and its local runoff appears only at
  the outlet's segment. In the 2026-10 build that is 2,184 of 36,380 sub-basins, holding 1,815 of
  22,184 m³/s (8%) of local runoff.
- A side channel carries the flow of outlets placed on it and its share of local runoff, not the main
  channel's flow.
- Known cases, listed by `sql/qa_report.sql` and open in NewGraphEnvironment/fwapg#8: 85 placed
  outlets carry more than 10 times PCIC's flow (mostly PCIC siblings that sit one above the other on
  the FWA, where flow follows the FWA); the Spillimacheen reaches the Columbia through a side channel
  15 km above where PCIC joins it, so the Columbia between reads about 54% high; Ansedagan Creek joins
  the Nass directly on the FWA while its PCIC outlet sits on a Nass side channel, so the creek carries
  almost nothing.
- Streams that leave BC before reaching their parent have no path, so their flow does not reach the
  parent in BC: the Okanagan, Kettle and Similkameen join the Columbia in the US, and their flow is not
  on the Columbia in BC (PCIC routes it through the US too).
- Monthly means of daily flow, 1951-2012, from the run driven by observed weather (PNWNAmet). The CMIP6
  runs, water temperature and dissolved-oxygen saturation are served the same way and are not processed.


### Data citation

Pacific Climate Impacts Consortium, University of Victoria (2026). Hydromosaic: routed streamflow, Raven
(VIC-GL), PNWNAmet historical run. https://beehive.pacificclimate.org/chyp/
