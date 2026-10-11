<!-- Draft PR into smnorris/fwapg main from NewGraphEnvironment:upstream-pcic-crosswalk. NOT POSTED: needs approval. -->

## PCIC routed streamflow on FWA streams (`extras/pcic_crosswalk`)

Stacked on the blue line paths PR (uses `extras/blue_line_paths`); merge that first.

PCIC publishes daily Raven-routed streamflow for about 48,700 sub-basin outlets (Fraser, Peace, Columbia, Kettle, Okanagan and BC coast) on its own river network, which shares no key with the FWA. This job crosswalks PCIC's outlets onto FWA streams, keeping PCIC's routing chain intact, and derives a 1951-2012 monthly flow climatology for every FWA segment below or within PCIC's network.

Outputs: `whse_basemapping.pcic_fwa_crosswalk` (48,716 outlets: 37,667 placed) and `whse_basemapping.fwa_stream_networks_discharge_monthly` (40.5 M rows, segment x month).

- `./pcic_crosswalk.sh`: downloads (cached, resumable) PCIC's network and the PNWNAmet run, snaps and places outlets, distributes flow, runs `sql/qa.sql` (10 tests) and stops before export if any fails. About 30 min with the downloads cached.
- `./qa_gauges.sh` checks against every WSC gauge in BC with discharge in the PCIC years: at 538 gauges, FWA flow within 10% of PCIC's at 494; the FWA stream picked matched the gauge's area within 10% at 559 of 603.
- `sql/qa_drainage.sql` flags placements whose drainage size disagrees with PCIC's (a review list).
- Ran end to end, as committed, on a full provincial load. Caveats and known cases are in the README.

Outputs are not uploaded anywhere by the job; `extras/README.md` is unchanged here, so where (or whether) to publish the csv.gz files is your call.
