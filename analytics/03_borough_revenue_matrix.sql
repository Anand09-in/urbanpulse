with matrix as (

    select
        pickup_borough,
        dropoff_borough,
        is_cross_borough,
        taxi_type,
        sum(trip_count)                         as total_trips,
        round(avg(avg_fare), 2)                 as avg_fare,
        round(avg(avg_distance), 2)             as avg_distance_miles,
        round(avg(avg_duration), 2)             as avg_duration_mins,
        round(sum(total_revenue), 2)            as total_revenue,
        round(avg(avg_tip_pct), 2)              as avg_tip_pct,
        round(avg(rush_hour_pct), 2)            as rush_hour_pct

    from mart_borough_comparison
    where year  = '2026'
      and month = '01'
      and pickup_borough  is not null
      and dropoff_borough is not null
    group by 1, 2, 3, 4

),

with_share as (

    select
        *,
        round(
            total_trips * 100.0
            / sum(total_trips) over (partition by taxi_type), 2
        )                                       as pct_of_all_trips

    from matrix

)

select
    pickup_borough,
    dropoff_borough,
    taxi_type,
    case when is_cross_borough
         then 'Cross-Borough' else 'Within Borough'
    end                                         as trip_type,
    total_trips,
    pct_of_all_trips,
    avg_fare,
    avg_distance_miles,
    avg_duration_mins,
    avg_tip_pct,
    total_revenue

from with_share
order by total_trips desc