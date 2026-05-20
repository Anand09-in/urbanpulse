-- No trip should be under 1 min or over 4 hours
select *
from {{ ref('stg_trips') }}
where trip_duration_mins < 1
   or trip_duration_mins > 240