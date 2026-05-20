with payment_summary as (

    select
        payment_label,
        pickup_borough,
        taxi_type,
        year,
        month,
        sum(trip_count)                         as total_trips,
        round(sum(total_fare), 2)               as total_fare,
        round(avg(avg_tip_pct), 2)              as avg_tip_pct,
        round(avg(payment_share_pct), 2)        as avg_payment_share

    from mart_payment_trends
    where payment_label in ('credit_card', 'cash')
    group by 1, 2, 3, 4, 5

),

with_totals as (

    select
        payment_label,
        pickup_borough,
        taxi_type,
        year,
        month,
        total_trips,
        total_fare,
        avg_tip_pct,

        -- share of trips within borough + taxi_type
        round(
            total_trips * 100.0
            / sum(total_trips) over (
                partition by pickup_borough, taxi_type, year, month
            ), 2
        )                                       as payment_share_pct,

        -- revenue per trip
        round(total_fare / nullif(total_trips, 0), 2) as revenue_per_trip

    from payment_summary

)

select
    payment_label,
    pickup_borough,
    taxi_type,
    year,
    month,
    total_trips,
    payment_share_pct,
    avg_tip_pct,
    revenue_per_trip,
    total_fare,

    -- cashless indicator: credit card dominance
    case
        when payment_label = 'credit_card'
         and payment_share_pct > 70 then 'Predominantly Cashless'
        when payment_label = 'credit_card'
         and payment_share_pct > 50 then 'Majority Cashless'
        else 'Mixed / Cash Heavy'
    end                                         as cashless_maturity

from with_totals
order by pickup_borough, payment_label, year, month