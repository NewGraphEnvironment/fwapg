# Findings — PCIC crosswalk: Nechako Reservoir outlets unplaced (#24)

## Issue context

**If we do it:** FWA segments in the Nechako Reservoir groups carry PCIC's routed flow, instead of about zero. **If we never do:** routed flow there is about zero on every segment, so any consumer (wet's default pick, NewGraphEnvironment/wet#57) has to fall back to another estimate across four watershed groups.

## What happens

In LEUT, UEUT and UNRS, routed flow in `fwa_stream_networks_discharge_monthly` is under 1 % of wet's open water balance on 97–100 % of segments, and LNRS is close behind. These four groups hold 73 % of the Fraser's near-zero routed segments (measured for wet#57 against fwapg 341b078, the #14 build).

PCIC has 487 outlets in the four groups (`fwapg.pcic_outlets` intersected with `fwa_watershed_groups_poly`):

| group | PCIC outlets | placed | flags |
|---|---|---|---|
| LEUT | 72 | 0 | broken_chain |
| UEUT | 203 | 0 | broken_chain, no_candidate |
| UNRS | 111 | 1 | broken_chain |
| LNRS | 101 | 3 | broken_chain |

PCIC's tree takes all 386 outlets of LEUT, UEUT and UNRS to the Fraser (root 4009421), and their `anchor_subid` lies in CHES. That suggests PCIC routes the reservoir out through the Skins Lake spillway and the Cheslatta, while the FWA reservoir drains another way. The chain breaks, the outlets stay unplaced, and their local runoff is given to the Cheslatta anchor's sub-basin. The FWA segments in the reservoir get almost none.

This is the "Nechako reservoir lakes" case in #6's gauge disagreements: wet's #58 report lists 08JA014, 08JA015, 08JA016 and 08JA028 at about 0 m³/s routed.

## Proposed

- Confirm the FWA's outlet of the reservoir, and PCIC's (`dowsubid` at the reservoir's lowest outlets).
- Decide how placement treats a reservoir both networks hold but drain differently. One option: give the reservoir's runoff to the FWA reservoir's own segments, and pass it on to whichever placed outlet the FWA reaches, so flow follows the FWA as the README says it does elsewhere.
- Check the regulated-flow flag on the Cheslatta (README, drainage check) against the result.

Relates to #6, #8.


## Errors Encountered

| Error | Resolution |
|-------|------------|
