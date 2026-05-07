-- Stars per day per repo, ranked by daily average.
-- Finds repos that are accelerating, not just historically popular.

WITH daily_stars AS (
    SELECT
        repo_name,
        day,
        count(*) AS stars_in_day
    FROM ghtrends_lake.raw
    WHERE event_type = 'WatchEvent'
      AND year = '2026'
      AND repo_name IS NOT NULL
    GROUP BY repo_name, day
),
agg AS (
    SELECT
        repo_name,
        sum(stars_in_day)            AS total_stars,
        avg(stars_in_day)            AS avg_daily_stars,
        max(stars_in_day)            AS peak_daily_stars,
        count(DISTINCT day)          AS active_days
    FROM daily_stars
    GROUP BY repo_name
)
SELECT *
FROM agg
WHERE total_stars >= 10  -- floor to filter noise
ORDER BY avg_daily_stars DESC
LIMIT 50;
