select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      -- Singular test: data quality check.
-- Passes if this query returns ZERO rows. If it returns any rows,
-- those rows have an event_date in the future, which means something
-- is wrong with the source data or our parsing.

select
    event_date,
    count(*) as bad_rows
from "awsdatacatalog"."ghtrends_lake"."fct_repo_trends_daily"
where event_date > current_date
group by event_date
      
    ) dbt_internal_test