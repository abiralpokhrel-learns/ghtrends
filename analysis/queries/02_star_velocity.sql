-- Star velocity: stars per day, then ranked.
-- Useful for finding repos that are accelerating, not just popular.

with daily as (
    select repo_name, event_date, stars
    from ghtrends_lake.fct_repo_trends_daily
    where event_date >= current_date - interval '14' day
),
agg as (
    select
        repo_name,
        sum(stars) as total_stars,
        avg(stars) as avg_daily_stars,
        max(stars) as peak_daily_stars
    from daily
    group by repo_name
)
select *
from agg
where total_stars >= 50  -- floor to filter noise
order by avg_daily_stars desc
limit 100;
