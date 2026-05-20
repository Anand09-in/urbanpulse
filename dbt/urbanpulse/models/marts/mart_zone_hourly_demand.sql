with trips as (

    select * from {{ ref('stg_trips') }}

),

aggregated as (

    select
        pickup_borough,
        pickup_zone,
        pickup_location_id,
        pickup_hour,
        pickup_day_of_week,
        is_weekend,
        is_rush_hour,
        taxi_type,
        year,
        month,

        count(*)                                     as trip_count,
        round(avg(fare_amount), 2)                   as avg_fare,
        round(avg(trip_distance_miles), 2)           as avg_distance_miles,
        round(avg(trip_duration_mins), 2)            as avg_duration_mins,
        round(avg(tip_pct), 2)                       as avg_tip_pct,
        round(sum(fare_amount), 2)                   as total_revenue,
        round(avg(passenger_count), 2)               as avg_passengers,

        -- speed proxy
        round(
            avg(trip_distance_miles /
                nullif(trip_duration_mins / 60.0, 0)), 2
        )                                            as avg_speed_mph

    from trips
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10

)

select * from aggregated