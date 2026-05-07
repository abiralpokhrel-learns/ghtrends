-- Emerging repos: ones that went from quiet to viral in the data window.
-- Definition: had at least one day under 10 stars AND a peak day of 50+ stars.

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
repo_summary AS (
    SELECT
        repo_name,
        min(stars_in_day)    AS min_daily_stars,
        max(stars_in_day)    AS peak_daily_stars,
        avg(stars_in_day)    AS avg_daily_stars,
        sum(stars_in_day)    AS total_stars,
        count(DISTINCT day)  AS active_days
    FROM daily_stars
    GROUP BY repo_name
)
SELECT *
FROM repo_summary
WHERE peak_daily_stars >= 50
  AND min_daily_stars < 10
  AND active_days >= 2
ORDER BY (peak_daily_stars - min_daily_stars) DESC
LIMIT 50;
