with tip_data as (

    select
        payment_type,
        payment_label,
        pickup_borough,
        taxi_type,
        is_rush_hour,
        year,
        month,
        sum(trip_count)                         as total_trips,
        round(avg(avg_tip_pct), 2)              as avg_tip_pct,
        round(sum(total_tips), 2)               as total_tips,
        round(sum(total_fare), 2)               as total_fare

    from mart_payment_trends
    where year        = '2026'
      and month       = '01'
      and payment_label in ('credit_card', 'cash')
    group by 1, 2, 3, 4, 5, 6, 7

),

with_index as (

    select
        *,
        -- tip index: how much above/below average this segment tips
        round(
            avg_tip_pct
            / nullif(avg(avg_tip_pct) over
                (partition by taxi_type, pickup_borough), 0)
            * 100, 1
        )                                       as tip_index

    from tip_data

)

select
    payment_label,
    pickup_borough,
    taxi_type,
    case when is_rush_hour
         then 'Rush Hour' else 'Off-Peak'
    end                                         as time_segment,
    total_trips,
    avg_tip_pct,
    tip_index,
    total_tips,

    -- What % of all tips come from this segment
    round(
        total_tips * 100.0
        / sum(total_tips) over (partition by taxi_type), 2
    )                                           as pct_of_total_tips

from with_index
order by avg_tip_pct desc