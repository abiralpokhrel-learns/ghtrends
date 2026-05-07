create or replace view
    "awsdatacatalog"."ghtrends_lake"."stg_watch_events"
  as
    -- One row per star event. Cleans column names and types.
-- Filters the unified raw table to WatchEvent rows.
--
-- Note: we use date_parse() instead of from_iso8601_timestamp() because the
-- latter returns "timestamp with time zone" which Athena's Hive metastore
-- can't store in a view. date_parse returns plain timestamp.

with src as (
    select *
    from "awsdatacatalog"."ghtrends_lake"."raw"
    where event_type = 'WatchEvent'
)

select
    id                                                              as event_id,
    actor_id,
    actor_login,
    repo_id,
    repo_name,
    date_parse(created_at, '%Y-%m-%dT%H:%i:%sZ')                    as created_at,
    cast(date_parse(created_at, '%Y-%m-%dT%H:%i:%sZ') as date)      as event_date
from src
where repo_name is not null
