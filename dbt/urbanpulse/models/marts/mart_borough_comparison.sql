with trips as (

    select * from {{ ref('stg_trips') }}

),

aggregated as (

    select
        pickup_borough,
        dropoff_borough,
        taxi_type,
        year,
        month,

        count(*)                                as trip_count,
        round(avg(fare_amount), 2)              as avg_fare,
        round(avg(trip_distance_miles), 2)      as avg_distance,
        round(avg(trip_duration_mins), 2)       as avg_duration,
        round(sum(fare_amount), 2)              as total_revenue,
        round(avg(tip_pct), 2)                  as avg_tip_pct,

        -- rush hour share
        round(
            sum(case when is_rush_hour then 1 else 0 end)
            * 100.0 / count(*), 2
        )                                       as rush_hour_pct,

        -- cross-borough flag
        case
            when pickup_borough != dropoff_borough
            then true else false
        end                                     as is_cross_borough

    from trips
    where pickup_borough is not null
      and dropoff_borough is not null
    group by 1, 2, 3, 4, 5

)

select * from aggregated