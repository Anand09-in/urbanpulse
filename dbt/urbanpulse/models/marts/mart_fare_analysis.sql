with trips as (

    select * from {{ ref('stg_trips') }}

),

fare_stats as (

    select
        pickup_borough,
        pickup_zone,
        taxi_type,
        payment_type,
        is_rush_hour,
        is_weekend,
        year,
        month,

        count(*)                                        as trip_count,
        round(avg(fare_amount), 2)                      as avg_fare,
        round(min(fare_amount), 2)                      as min_fare,
        round(max(fare_amount), 2)                      as max_fare,

        -- tip behaviour
        round(avg(tip_pct), 2)                          as avg_tip_pct,
        round(avg(case when tip_amount > 0
                  then tip_pct end), 2)                 as avg_tip_pct_when_tipped,
        round(
            sum(case when tip_amount > 0 then 1 else 0 end)
            * 100.0 / count(*), 2
        )                                               as pct_trips_with_tip,

        -- revenue
        round(sum(fare_amount), 2)                      as total_fare_revenue,
        round(sum(tip_amount), 2)                       as total_tip_revenue,
        round(sum(total_amount), 2)                     as total_revenue

    from trips
    group by 1, 2, 3, 4, 5, 6, 7, 8

)

select * from fare_stats