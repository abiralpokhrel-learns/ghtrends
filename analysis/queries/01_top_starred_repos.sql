-- Top 50 repos by total stars over the past 7 days.
-- Run against the dbt mart from Phase 4 (fct_repo_trends_daily).

select
    repo_name,
    sum(stars)               as stars_7d,
    count(distinct event_date) as active_days
from ghtrends_lake.fct_repo_trends_daily
where event_date >= current_date - interval '7' day
group by repo_name
order by stars_7d desc
limit 50;
