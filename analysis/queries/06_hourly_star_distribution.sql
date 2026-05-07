-- What hour of UTC sees the most stars?
-- Reveals open-source community timezone patterns.
-- Result: 24 rows, one per hour.

SELECT
    hour      AS utc_hour,
    count(*)  AS stars
FROM ghtrends_lake.raw
WHERE event_type = 'WatchEvent'
  AND year = '2026'
GROUP BY hour
ORDER BY hour;
