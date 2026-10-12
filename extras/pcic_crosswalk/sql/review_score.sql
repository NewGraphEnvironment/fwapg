-- Score a filled-in review GeoPackage against its sample design
-- (NewGraphEnvironment/fwapg#8). review_score.sh loads the temporary tables
-- design (review_id, subid, stratum, drawn) and review (the GeoPackage's review
-- layer) in the same session first: psql does not interpolate variables in \copy.
-- Refuses, with an error, a review layer that does not belong to the design or
-- holds values outside the form's.
--
-- An outlet counts toward each stratum that drew it (drawn = t). It is also
-- listed in strata it belongs to without being drawn, so membership is known,
-- but those rows never enter a rate: the random stratum's rate is the error rate
-- over placed outlets only because nothing drawn for a flag list leaks into it.
-- A blank verdict is unreviewed, not an error; a blank confidence is high.

DO $$
DECLARE
  dup integer;
  missing integer;
  extra integer;
  bad text;
BEGIN
  SELECT count(*) INTO dup FROM (SELECT review_id FROM review GROUP BY review_id HAVING count(*) > 1) d;
  IF dup > 0 OR EXISTS (SELECT 1 FROM review WHERE review_id IS NULL) THEN
    RAISE EXCEPTION 'refused: % review_id values repeat in the review layer, % features have none',
      dup, (SELECT count(*) FROM review WHERE review_id IS NULL);
  END IF;
  SELECT count(*) INTO missing FROM (SELECT DISTINCT review_id FROM design) d
    WHERE NOT EXISTS (SELECT 1 FROM review r WHERE r.review_id = d.review_id);
  SELECT count(*) INTO extra FROM review r
    WHERE NOT EXISTS (SELECT 1 FROM design d WHERE d.review_id = r.review_id);
  IF missing > 0 OR extra > 0 THEN
    RAISE EXCEPTION 'refused: the review_id set is not the design''s: % missing, % not in the design', missing, extra;
  END IF;
  SELECT string_agg(DISTINCT verdict, ', ') INTO bad FROM review
    WHERE nullif(trim(verdict), '') NOT IN ('right', 'wrong_stream', 'wrong_position', 'should_not_be_placed', 'should_be_placed');
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'refused: unknown verdict %', bad;
  END IF;
  SELECT string_agg(DISTINCT confidence, ', ') INTO bad FROM review
    WHERE nullif(trim(confidence), '') NOT IN ('high', 'low');
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'refused: unknown confidence %', bad;
  END IF;
END $$;

CREATE TEMPORARY VIEW scored AS
SELECT
  d.stratum,
  d.review_id,
  d.drawn,
  nullif(trim(r.verdict), '') AS verdict,
  coalesce(nullif(trim(r.confidence), ''), 'high') AS confidence
FROM (SELECT DISTINCT review_id, stratum, drawn FROM design) d
INNER JOIN review r ON r.review_id = d.review_id;

-- per stratum: drawn, reviewed, errors (any verdict but 'right'), rate and its
-- 95% Wilson interval (which stays within 0 and 1 by construction: no greatest()
-- or least() clamp, as they ignore NULL and would put 0 and 1 on a stratum with
-- nothing reviewed)
SELECT 'stratum|drawn|reviewed|errors|rate|lo95|hi95';
WITH s AS (
  SELECT
    stratum,
    count(*) FILTER (WHERE drawn) AS drawn,
    count(*) FILTER (WHERE drawn AND verdict IS NOT NULL) AS n,
    count(*) FILTER (WHERE drawn AND verdict != 'right') AS e
  FROM scored
  GROUP BY stratum
),
w AS (
  SELECT s.*, nullif(n, 0)::numeric AS m, e::numeric / nullif(n, 0) AS p, 1.959964 AS z FROM s
)
SELECT
  stratum, drawn, n, e,
  round(p, 3),
  round(((p + z ^ 2 / (2 * m) - z * sqrt(p * (1 - p) / m + z ^ 2 / (4 * m ^ 2))) / (1 + z ^ 2 / m)), 3),
  round(((p + z ^ 2 / (2 * m) + z * sqrt(p * (1 - p) / m + z ^ 2 / (4 * m ^ 2))) / (1 + z ^ 2 / m)), 3)
FROM w
ORDER BY stratum != 'random', stratum;

-- verdicts per stratum, drawn outlets only
SELECT '';
SELECT 'stratum|verdict|n';
SELECT stratum, coalesce(verdict, '(unreviewed)'), count(*)
FROM scored
WHERE drawn
GROUP BY 1, 2
ORDER BY stratum != 'random', 1, 2;

-- errors in the random stratum that no automatic check flagged (the line-following
-- check, or the drainage, gauge and flow flags), and low-confidence verdicts
SELECT '';
SELECT 'random errors in no flagged stratum|' || count(*)
FROM scored s
WHERE s.stratum = 'random' AND s.drawn AND s.verdict != 'right'
AND NOT EXISTS (
  SELECT 1 FROM design d WHERE d.review_id = s.review_id AND d.stratum IN ('following', 'flagged')
);
SELECT 'random low confidence|' || count(*)
FROM scored
WHERE stratum = 'random' AND drawn AND verdict IS NOT NULL AND confidence = 'low';
