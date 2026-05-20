-- Tip percentage should never be negative
select *
from {{ ref('stg_trips') }}
where tip_pct < 0