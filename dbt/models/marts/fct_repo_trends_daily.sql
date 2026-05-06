-- Final daily trend mart. Plain table (Parquet in S3, registered in Glue).
-- v2 plan: no Iceberg. Append-only data with date partitions doesn't need it.

{{ config(materialized='table') }}

select
    repo_id,
    repo_name,
    event_date,
    stars,
    prs_opened,
    prs_merged,
    prs_closed_unmerged,
    case
        when (prs_opened + prs_merged + prs_closed_unmerged) = 0 then null
        else cast(prs_merged as double)
             / nullif((prs_merged + prs_closed_unmerged), 0)
    end as pr_merge_rate,
    sum(stars) over (
        partition by repo_id
        order by event_date
        rows between 6 preceding and current row
    ) as stars_7d_rolling
from {{ ref('int_repo_daily_activity') }}
