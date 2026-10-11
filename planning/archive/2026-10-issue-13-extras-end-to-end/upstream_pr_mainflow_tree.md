<!-- Draft PR into smnorris/fwapg main from NewGraphEnvironment:upstream-mainflow-tree. NOT POSTED: needs approval. Refreshed 2026-10-11 for the SSNbler fix (#16); rebuild the branch from newgraph before posting. -->

## Main-flow tree (`extras/mainflow_tree`)

Stacked on the blue line paths PR (uses `extras/blue_line_paths`); merge that first.

A dendritic subset of `fwa_stream_networks_sp`, for models that need a stream network with no splits (SSN2/SSNbler spatial stream network models, additive function values, flow accumulation), computed by rule rather than hand-picked segments: main flow (`blue_line_key = watershed_key`), plus each side channel a main-flow tributary drains through, kept from where the water enters it down; cut-offs followed down while there is one way down; one override.

Output: `whse_basemapping.fwa_stream_networks_mainflow_tree` (`linear_feature_id`, `watershed_group_code`, `blue_line_key`, `source`), 4,510,368 segments.

- **0 splits** province-wide (the network has 74,426), **8 cut-offs** (main flow alone: 28,870). The 473 dead ends and 23 outlets with no parent inside BC are gaps in the FWA geometry, listed in `data/qa_topology.csv`.
- `./mainflow_tree.sh`: rebuilds the paths, builds the tree (3 min), runs the topology QA (1.5 min) and `sql/qa.sql` (10 tests), and exports.
- `ssnbler_check.R` / `ssnbler_check.sh` check a subset with `SSNbler::lines_to_lsn(check_topology = TRUE)` (the shell driver runs one check at a time under a memory cap). SSNbler 1.1.2 reports false node errors on FWA data from two defects, which `ssnbler_reprex.R` reproduces with synthetic lines; the fix is offered as pet221/SSNbler#9, and the README installs it from a fork, pinned, until it is released. On 1.1.2, 27 of 29 Skeena and Nechako watershed groups and the whole Nechako (210,000 lines, with the 8 outlets counted in SQL) have 0 node errors. The other two groups and the whole Skeena report only those false errors, and are clean with the fix (the Skeena with 1 outlet).
- Ran end to end, as committed, on a full provincial load.
