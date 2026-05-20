with demand as (

    select
        pickup_borough,
        pickup_zone,
        pickup_hour,
        is_rush_hour,
        taxi_type,
        sum(trip_count)      as total_trips,
        round(avg(avg_fare), 2) as avg_fare,
        round(sum(total_revenue), 2) as total_revenue

    from mart_zone_hourly_demand
    where year  = '2026'
      and month = '01'
    group by 1, 2, 3, 4, 5

),

ranked as (

    select
        *,
        row_number() over (
            partition by is_rush_hour
            order by total_trips desc
        ) as demand_rank

    from demand

)

select
    demand_rank                     as rank,
    pickup_borough,
    pickup_zone,
    taxi_type,
    case when is_rush_hour
         then 'Rush Hour (7-9am, 5-7pm)'
         else 'Off-Peak'
    end                             as time_segment,
    total_trips,
    avg_fare,
    total_revenue

from ranked
where demand_rank <= 10
order by is_rush_hour desc, demand_rank