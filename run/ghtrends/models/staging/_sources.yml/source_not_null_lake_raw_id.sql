select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select id
from "awsdatacatalog"."ghtrends_lake"."raw"
where id is null



      
    ) dbt_internal_test