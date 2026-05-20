-- This query must return 0 rows to pass
select *
from {{ ref('stg_trips') }}
where fare_amount < 3.0
  and taxi_type in ('yellow', 'green')