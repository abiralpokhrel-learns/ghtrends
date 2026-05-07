-- One row per pull request event. Cleans column names and types.
-- Filters the unified raw table to PullRequestEvent rows.
--
-- See stg_watch_events.sql for why we use date_parse() not from_iso8601_timestamp().

with src as (
    select *
    from "awsdatacatalog"."ghtrends_lake"."raw"
    where event_type = 'PullRequestEvent'
)

select
    id                                                              as event_id,
    actor_id,
    actor_login,
    repo_id,
    repo_name,
    pr_action,
    pr_merged,
    pr_state,
    pr_base_ref,
    pr_user_login,
    date_parse(created_at, '%Y-%m-%dT%H:%i:%sZ')                    as created_at,
    cast(date_parse(created_at, '%Y-%m-%dT%H:%i:%sZ') as date)      as event_date
from src
where repo_name is not null