with city_stats as (

    select
        avg(avg_fare)                   as city_avg_fare,
        stddev_pop(avg_fare)            as city_stddev_fare
    from mart_fare_analysis
    where year  = '2026'
      and month = '01'

),

zone_stats as (

    select
        pickup_borough,
        pickup_zone,
        taxi_type,
        round(avg(avg_fare), 2)         as zone_avg_fare,
        round(sum(trip_count), 0)       as total_trips,
        round(sum(total_fare_revenue), 2) as total_revenue

    from mart_fare_analysis
    where year  = '2026'
      and month = '01'
    group by 1, 2, 3

),

anomalies as (

    select
        z.*,
        c.city_avg_fare,
        c.city_stddev_fare,
        round(
            (z.zone_avg_fare - c.city_avg_fare)
            / nullif(c.city_stddev_fare, 0), 2
        )                               as z_score,

        case
            when (z.zone_avg_fare - c.city_avg_fare)
                 / nullif(c.city_stddev_fare, 0) > 2
            then 'HIGH — possible surge or long-distance zone'
            when (z.zone_avg_fare - c.city_avg_fare)
                 / nullif(c.city_stddev_fare, 0) < -2
            then 'LOW — possible short-trip or flat-rate zone'
            else 'NORMAL'
        end                             as anomaly_flag

    from zone_stats z
    cross join city_stats c

)

select
    pickup_borough,
    pickup_zone,
    taxi_type,
    zone_avg_fare,
    round(city_avg_fare, 2)             as city_avg_fare,
    z_score,
    total_trips,
    anomaly_flag

from anomalies
where anomaly_flag != 'NORMAL'
order by abs(z_score) desc
limit 25