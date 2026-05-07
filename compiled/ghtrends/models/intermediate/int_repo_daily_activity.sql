-- One row per repo per day. Combines stars and PR activity into a single
-- intermediate table. Marts (fct_repo_trends_daily) read from this.
--
-- Note on uniqueness: we group by (repo_id, event_date) only and pick
-- max(repo_name) for the name. GitHub repos can be renamed, so the same
-- repo_id may appear with multiple names — without this, the unique test
-- on (repo_id, event_date) in the mart would fail.

with stars as (
    select
        repo_id,
        max(repo_name) as repo_name,
        event_date,
        count(*)       as stars
    from "awsdatacatalog"."ghtrends_lake"."stg_watch_events"
    where repo_id is not null
    group by repo_id, event_date
),

prs as (
    -- Note: pr_merged is integer (0/1) in the raw Parquet because pyarrow
    -- stored it that way. Compare to 1/0, not true/false.
    select
        repo_id,
        max(repo_name) as repo_name,
        event_date,
        sum(case when pr_action = 'opened' then 1 else 0 end)                       as prs_opened,
        sum(case when pr_merged = 1 then 1 else 0 end)                              as prs_merged,
        sum(case when pr_action = 'closed' and pr_merged = 0 then 1 else 0 end)     as prs_closed_unmerged
    from "awsdatacatalog"."ghtrends_lake"."stg_pull_request_events"
    where repo_id is not null
    group by repo_id, event_date
)

select
    coalesce(s.repo_id, p.repo_id)         as repo_id,
    coalesce(s.repo_name, p.repo_name)     as repo_name,
    coalesce(s.event_date, p.event_date)   as event_date,
    coalesce(s.stars, 0)                   as stars,
    coalesce(p.prs_opened, 0)              as prs_opened,
    coalesce(p.prs_merged, 0)              as prs_merged,
    coalesce(p.prs_closed_unmerged, 0)     as prs_closed_unmerged
from stars s
full outer join prs p
    on s.repo_id    = p.repo_id
   and s.event_date = p.event_date