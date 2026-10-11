<!-- Draft PR into smnorris/fwapg main from NewGraphEnvironment:upstream-mainflow-tree. NOT POSTED: needs approval. -->

## Main-flow tree (`extras/mainflow_tree`)

Stacked on the blue line paths PR (uses `extras/blue_line_paths`); merge that first.

A dendritic subset of `fwa_stream_networks_sp`, for models that need a stream network with no splits (SSN2/SSNbler spatial stream network models, additive function values, flow accumulation), computed by rule rather than hand-picked segments: main flow (`blue_line_key = watershed_key`), plus each side channel a main-flow tributary drains through, kept from where the water enters it down; cut-offs followed down while there is one way down; one override.

Output: `whse_basemapping.fwa_stream_networks_mainflow_tree` (`linear_feature_id`, `watershed_group_code`, `blue_line_key`, `source`), 4,510,368 segments.

- **0 splits** province-wide (the network has 74,426), **8 cut-offs** (main flow alone: 28,870). The 473 dead ends and 23 outlets with no parent inside BC are gaps in the FWA geometry, listed in `data/qa_topology.csv`.
- `./mainflow_tree.sh`: rebuilds the paths, builds the tree (3 min), runs the topology QA (1.5 min) and `sql/qa.sql` (10 tests), and exports.
- `ssnbler_check.R` / `ssnbler_check.sh` check a subset with `SSNbler::lines_to_lsn(check_topology = TRUE)` (the shell driver runs one check at a time under a memory cap). All Skeena and Nechako watershed groups: 0 node errors except one cm-long segment in each of two groups; the whole Nechako (210,000 lines) has 0 node errors and the 8 outlets counted in SQL. The README notes an SSNbler parallel-path quirk in its unsnapped-node test.
- Ran end to end, as committed, on a full provincial load.
