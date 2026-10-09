## Blue line downstream paths

The downstream path of every FWA blue line: the chain of blue lines its water passes through to the sea,
with the measure at which it joins each. Shared by `extras/pcic_crosswalk` (every "is b on or upstream of a"
comparison) and `extras/mainflow_tree` (which side channels a main-flow tributary drains through). Each of
those jobs rebuilds it first.

Local codes cannot order positions across blue lines (`research/fwa_position_codes.md`), so `FWA_Upstream`
is not used for this.


## Processing

    ./blue_line_paths.sh

Builds the tables (about 35 min province-wide, measured 2026-10-09 on a local Docker database; almost all of it is matching each mouth to the lines it touches, about 1.2 ms per line), then runs the tests in `sql/qa.sql` and stops if any fails.

A line's parent and junction come from, in order (the header of `sql/blue_line_paths.sql` has the detail and
the cases each rule fixed):

1. **Code junction** (main stems): the lowest segment of the parent watershed code's main stem whose local
   code equals the line's watershed code. Deferred when the mouth touches a side channel of that main stem.
2. **Touch**: the line its mouth touches (within 1 m) further down by watershed code, or a side channel's
   own main stem.
3. **Rounds**: the line its mouth touches that already has a parent; braids rejoin through sibling braids.
4. The deferred code junctions, then rounds again.
5. **Side channel fallback**: a side channel's own main stem, by local code or within 1 km; then rounds
   again.
6. Otherwise no parent: the line's water leaves BC before it reaches its parent, or it has no parent code
   in BC.

The parents cannot form a cycle (argued in the SQL header, and checked: the build fails if a path ends in
one).


## Output

    Table "fwapg.blk_parents"
          Column          |       Type       |
    ----------------------+------------------+----------------------------------------------------------
     blue_line_key        | integer          | primary key
     parent_blue_line_key | integer          | the line its water enters
     junction_measure     | double precision | measure on the parent where it enters
     junction_gap_m       | double precision | distance from the mouth to the junction (0 when it touches)
     junction_method      | text             | code, touch, touch_round, code_deferred, side_fallback
     round                | integer          |

    Table "fwapg.blk_paths"
        Column     |        Type        |
    ---------------+--------------------+---------------------------------------------
     blue_line_key | integer            | primary key
     path_blks     | integer[]          | parent, grandparent, ... to the last line
     path_measures | double precision[] | junction measure on each

    Function fwapg.blk_on_or_upstream(blk_a, drm_a, blk_b, drm_b) -> boolean
      true when position b is on or upstream of position a
