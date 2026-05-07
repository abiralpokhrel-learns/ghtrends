

with meet_condition as(
  select *
  from "awsdatacatalog"."ghtrends_lake"."fct_repo_trends_daily"
),

validation_errors as (
  select *
  from meet_condition
  where
    -- never true, defaults to an empty result set. Exists to ensure any combo of the `or` clauses below succeeds
    1 = 2
    -- records with a value >= min_value are permitted. The `not` flips this to find records that don't meet the rule.
    or not pr_merge_rate >= 0
    -- records with a value <= max_value are permitted. The `not` flips this to find records that don't meet the rule.
    or not pr_merge_rate <= 1
)

select *
from validation_errors

