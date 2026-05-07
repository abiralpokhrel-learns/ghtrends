-- Top 50 repos by total stars in the data window.
-- Runs against ghtrends_lake.raw (Phase 3 single-table layout).
-- In Phase 4 this will move to read from fct_repo_trends_daily.

SELECT
    repo_name,
    count(*) AS stars
FROM ghtrends_lake.raw
WHERE event_type = 'WatchEvent'
  AND year = '2026'
  AND repo_name IS NOT NULL
GROUP BY repo_name
ORDER BY stars DESC
LIMIT 50;
