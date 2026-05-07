-- Top organizations by total event volume.
-- Repo names are "org/repo" — split_part extracts the org part.

SELECT
    split_part(repo_name, '/', 1) AS org_name,
    count(*)                      AS event_count,
    count(DISTINCT repo_name)     AS unique_repos,
    count(DISTINCT CASE WHEN event_type = 'WatchEvent' THEN actor_login END) AS unique_starrers
FROM ghtrends_lake.raw
WHERE year = '2026'
  AND repo_name IS NOT NULL
GROUP BY split_part(repo_name, '/', 1)
ORDER BY event_count DESC
LIMIT 50;
