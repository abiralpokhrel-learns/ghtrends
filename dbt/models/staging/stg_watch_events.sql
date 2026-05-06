-- One row per star event. Cleans column names and types.

with src as (
    select * from {{ source('lake', 'watch_events') }}
)

select
    id                                      as event_id,
    actor_id,
    actor_login,
    repo_id,
    repo_name,
    cast(created_at as timestamp)           as created_at,
    cast(date(created_at) as date)          as event_date
from src
