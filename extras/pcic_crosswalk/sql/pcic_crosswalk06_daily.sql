-- Flow per sub-basin and day, from outlet flow per day: fwapg.:src (subid, month,
-- day, q_m3s) into fwapg.:dst (subid, month, day, q_local, q_acc). Run by
-- pcic_crosswalk06_subbasins.sql on the run's calendar-day climatology
-- (pcic_outlet_daily into pcic_subbasins_daily), and by pcic_crosswalk.sh on each
-- year of the model's series (pcic_outlet_year into pcic_subbasins_year). Reads by
-- name fwapg.pcic_outlets (subid, dowsubid), fwapg.pcic_fwa_crosswalk (flag,
-- anchor_subid, fwa_parent_subid) and fwapg.pcic_subbasins (subid, fwa_depth),
-- which pcic_crosswalk06_subbasins.sql leaves.
--
-- Every step is linear in the flows, so a period's mean of q_local or q_acc
-- (pcic_crosswalk08_periods.sql), or a mean over years, equals the same steps run
-- on the period's mean outlet flows.

-- flow generated inside each placed outlet's sub-basin
DROP TABLE IF EXISTS fwapg.:dst;

-- built in sub-basin order, with half of each page left free, so that the
-- accumulation below reads a sub-basin's days from a few pages and updates them in
-- place (a heap-only update), rather than moving each row to a page of its own
CREATE TABLE fwapg.:dst WITH (fillfactor = 50) AS
WITH runoff AS (
  SELECT
    o.subid,
    q.month,
    q.day,
    q.q_m3s - coalesce(sum(qc.q_m3s), 0) AS q_runoff
  FROM fwapg.pcic_outlets o
  INNER JOIN fwapg.:src q ON o.subid = q.subid
  LEFT JOIN fwapg.pcic_outlets c ON c.dowsubid = o.subid
  LEFT JOIN fwapg.:src qc ON qc.subid = c.subid AND qc.month = q.month AND qc.day = q.day
  GROUP BY o.subid, q.month, q.day, q.q_m3s
)
SELECT
  sb.subid,
  r.month,
  r.day,
  sum(r.q_runoff) AS q_local,
  sum(r.q_runoff) AS q_acc
FROM runoff r
INNER JOIN fwapg.pcic_fwa_crosswalk x ON r.subid = x.subid
INNER JOIN fwapg.pcic_subbasins sb
  ON sb.subid = CASE WHEN x.flag IS NULL THEN x.subid ELSE x.anchor_subid END
GROUP BY sb.subid, r.month, r.day
ORDER BY sb.subid, r.month, r.day;

ALTER TABLE fwapg.:dst ADD PRIMARY KEY (subid, month, day);

ANALYZE fwapg.:dst;

-- flow accumulated at each placed outlet: its own local flow plus the
-- accumulated flow of the outlets directly above it, resolved from the top of the
-- FWA tree down. q_acc starts as q_local. The outlets directly above an outlet at
-- FWA depth d are all at depth d + 1, so going up from the deepest level, each
-- level adds its children's finished totals. psql substitutes no variable inside
-- the dollar-quoted body, so the table's name reaches it as a setting.
SELECT set_config('pcic.dst', :'dst', false) \gset

DO $$
DECLARE
  d integer;
  maxdepth integer;
BEGIN
  SELECT max(fwa_depth) INTO maxdepth FROM fwapg.pcic_subbasins;
  FOR d IN REVERSE maxdepth - 1..0 LOOP
    EXECUTE format($f$
      UPDATE fwapg.%1$I m
      SET q_acc = m.q_acc + c.q_acc
      FROM (
        SELECT x.fwa_parent_subid AS subid, cm.month, cm.day, sum(cm.q_acc) AS q_acc
        FROM fwapg.pcic_subbasins sb
        INNER JOIN fwapg.pcic_fwa_crosswalk x ON x.subid = sb.subid
        INNER JOIN fwapg.%1$I cm ON cm.subid = sb.subid
        WHERE sb.fwa_depth = $1 + 1
        GROUP BY x.fwa_parent_subid, cm.month, cm.day
      ) c
      WHERE m.subid = c.subid
      AND m.month = c.month
      AND m.day = c.day$f$, current_setting('pcic.dst')) USING d;
  END LOOP;
END $$;

ANALYZE fwapg.:dst;
