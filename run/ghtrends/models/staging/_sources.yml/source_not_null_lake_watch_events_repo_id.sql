select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select repo_id
from "awsdatacatalog"."ghtrends_lake"."watch_events"
where repo_id is null



      
    ) dbt_internal_test