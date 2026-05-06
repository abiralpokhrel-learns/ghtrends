-- One row per repo per day. Combines stars and PRs into a single activity table.

with stars as (
    select
        repo_id,
        repo_name,
        event_date,
        count(*) as stars
    from {{ ref('stg_watch_events') }}
    group by 1, 2, 3
),

prs as (
    select
        repo_id,
        repo_name,
        event_date,
        count(*) filter (where pr_action = 'opened') as prs_opened,
        count(*) filter (where pr_merged = true)    as prs_merged,
        count(*) filter (where pr_action = 'closed' and pr_merged = false) as prs_closed_unmerged
    from {{ ref('stg_pull_request_events') }}
    group by 1, 2, 3
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
