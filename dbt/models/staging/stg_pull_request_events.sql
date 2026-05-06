-- One row per pull request event. Cleans column names and types.

with src as (
    select * from {{ source('lake', 'pull_request_events') }}
)

select
    id                                      as event_id,
    actor_id,
    actor_login,
    repo_id,
    repo_name,
    pr_action,
    pr_merged,
    pr_state,
    pr_base_ref,
    pr_user_login,
    cast(created_at as timestamp)           as created_at,
    cast(date(created_at) as date)          as event_date
from src
