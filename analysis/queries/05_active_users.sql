-- Top users by total activity (stars given + PRs opened).
-- Filters to users with >= 5 events to avoid one-time accounts.

SELECT
    actor_login,
    sum(CASE WHEN event_type = 'WatchEvent' THEN 1 ELSE 0 END) AS stars_given,
    sum(CASE WHEN event_type = 'PullRequestEvent' AND pr_action = 'opened' THEN 1 ELSE 0 END) AS prs_opened,
    count(DISTINCT repo_name) AS unique_repos_touched,
    count(*) AS total_events
FROM ghtrends_lake.raw
WHERE year = '2026'
  AND actor_login IS NOT NULL
GROUP BY actor_login
HAVING count(*) >= 5
ORDER BY total_events DESC
LIMIT 50;
