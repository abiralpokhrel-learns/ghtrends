select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select event_date
from "awsdatacatalog"."ghtrends_lake"."fct_repo_trends_daily"
where event_date is null



      
    ) dbt_internal_test