-- PR merge rate per repo over the last 30 days.
-- Filters out tiny repos that distort percentages.

select
    repo_name,
    sum(prs_opened)                     as opened,
    sum(prs_merged)                     as merged,
    sum(prs_closed_unmerged)            as closed_unmerged,
    cast(sum(prs_merged) as double)
        / nullif(sum(prs_merged + prs_closed_unmerged), 0) as merge_rate
from ghtrends_lake.fct_repo_trends_daily
where event_date >= current_date - interval '30' day
group by repo_name
having sum(prs_merged + prs_closed_unmerged) >= 20  -- floor
order by merge_rate desc
limit 100;
