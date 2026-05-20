with trips as (

    select * from {{ ref('stg_trips') }}

),

-- Map payment type codes to labels
payment_labelled as (

    select
        *,
        case payment_type
            when 1 then 'credit_card'
            when 2 then 'cash'
            when 3 then 'no_charge'
            when 4 then 'dispute'
            when 5 then 'unknown'
            when 6 then 'voided_trip'
            else        'other'
        end as payment_label

    from trips

),

aggregated as (

    select
        payment_type,
        payment_label,
        pickup_borough,
        taxi_type,
        is_rush_hour,
        year,
        month,

        count(*)                                        as trip_count,
        round(sum(fare_amount), 2)                      as total_fare,
        round(sum(tip_amount), 2)                       as total_tips,
        round(avg(tip_pct), 2)                          as avg_tip_pct,

        -- payment share
        round(
            count(*) * 100.0 /
            sum(count(*)) over (partition by year, month, pickup_borough), 2
        )                                               as payment_share_pct

    from payment_labelled
    group by 1, 2, 3, 4, 5, 6, 7

)

select * from aggregated