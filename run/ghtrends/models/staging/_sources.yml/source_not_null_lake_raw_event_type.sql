select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select event_type
from "awsdatacatalog"."ghtrends_lake"."raw"
where event_type is null



      
    ) dbt_internal_test