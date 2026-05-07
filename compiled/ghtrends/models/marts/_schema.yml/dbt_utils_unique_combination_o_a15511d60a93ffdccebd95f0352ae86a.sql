





with validation_errors as (

    select
        repo_id, event_date
    from "awsdatacatalog"."ghtrends_lake"."fct_repo_trends_daily"
    group by repo_id, event_date
    having count(*) > 1

)

select *
from validation_errors


