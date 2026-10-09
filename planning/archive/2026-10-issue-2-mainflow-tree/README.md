## Outcome
Added a main-flow tree (`extras/mainflow_tree`, `whse_basemapping.fwa_stream_networks_mainflow_tree`): a dendritic subset of the FWA stream network for SSN2/SSNbler-style models, computed by rule instead of hand-picked segments. Main flow (`blue_line_key = watershed_key`) has no splits but cuts off every tributary whose mouth is on a side channel. Each such side channel is kept from the tributary's entry down, with its route taken from the blue line downstream paths the PCIC crosswalk already built; those paths moved to a shared job (`extras/blue_line_paths`) with a behaviour-preserving rename. Measuring added three rules: no reattachment for a mouth already on main flow, following cut-offs while there is one way down, and one override (the Beaver River). Learned: the paths' 1 m touch tolerance is right for flow and too loose for topology; FWA geometry leaves 473 dead ends no subset can close; SSNbler memory is roughly quadratic in lines and it rounds nodes by `snap_tolerance`. Durable findings are in `research/fwa_mainflow_tree.md`.

## Measurement
- Province-wide tree: 4,510,368 segments (4,451,744 main flow, 58,447 reattached on 19,745 side channels, 177 followed, 1 override exclusion). **0 splits** (the network has 74,426); **8 cut-offs**, against 28,870 for main flow alone.
- Every tree segment whose water continues nowhere in the tree is classed by measurement: 8 cut-offs, 473 dead ends (354 main stems off their code junction, 119 fallback side channels), 26,690 mouths with no parent at BC's edge, 23 with no parent inside BC.
- Reattachment alone gave 7 split nodes and 97 cut-offs; each later rule is in `findings.md` with the counts it removed.
- Acceptance (fwapg#2): all 26 Skeena connectors, the four side-channel paths and the Chilako-Nechako connection reproduced (10/10 QA tests). SSNbler: 24 of 26 Skeena/Nechako groups 0 node errors; USKE and MSKE one spot each at a 1.6 / 2.9 cm segment (geometry a plain chain); the LSKE window around 360216952 clean. Skeena basin 1 outlet; Nechako 8 (mouth, 6 dead ends, 1 no-parent).
- PCIC refactor: parents/paths identical (1,570,499 lines); crosswalk and 40,524,612 monthly rows identical, max |dq| 0.
- Runtimes: paths 35 min (not the 4-6 min recorded before), tree 1 min, topology QA ~35 min. SSNbler 1.5 GB at 5,500 lines, 39 GB at 24,000.
- Wrong turns kept: first build had 7 splits (strict-measure and near-top touches); SSNbler "divergences" first blamed on `topo_tolerance` (no change at 1 cm), then traced to `snap_tolerance` rounding; three parallel SSNbler runs caused three kernel panics (rtj#379); outlet labels corrected over code-check rounds 3-4 until every outlet was classified by query.
- Code-check: plan review + 4 rounds (round 1 rerun after a reboot lost it); findings and fixes in `review-*.md`; ended by enumeration of all 27,194 non-continuing tree segments.

## Evidence
Local, gitignored: `extras/mainflow_tree/data/ssnbler/*.log` (per-group SSNbler runs; `serial2.log` is the committed-script run), `extras/mainflow_tree/data/qa_topology.csv`.

Closed by: PR into `newgraph` (branch `2-main-flow-tree-a-dendritic-stream-networ`)
