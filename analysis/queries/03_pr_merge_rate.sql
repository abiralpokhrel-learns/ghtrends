-- PR merge rate per repo.
-- Filters to repos with >= 5 closed PRs to avoid noisy percentages.
--
-- Note: the Glue Crawler inferred pr_merged as integer (0/1), not boolean,
-- so we compare to 1/0 instead of true/false.

WITH pr_counts AS (
    SELECT
        repo_name,
        sum(CASE WHEN pr_action = 'opened' THEN 1 ELSE 0 END) AS prs_opened,
        sum(CASE WHEN pr_merged = 1 THEN 1 ELSE 0 END)        AS prs_merged,
        sum(CASE WHEN pr_action = 'closed' AND pr_merged = 0 THEN 1 ELSE 0 END) AS prs_closed_unmerged
    FROM ghtrends_lake.raw
    WHERE event_type = 'PullRequestEvent'
      AND year = '2026'
      AND repo_name IS NOT NULL
    GROUP BY repo_name
)
SELECT
    repo_name,
    prs_opened,
    prs_merged,
    prs_closed_unmerged,
    CAST(prs_merged AS DOUBLE)
        / NULLIF(prs_merged + prs_closed_unmerged, 0) AS merge_rate
FROM pr_counts
WHERE (prs_merged + prs_closed_unmerged) >= 5
ORDER BY merge_rate DESC
LIMIT 50;
