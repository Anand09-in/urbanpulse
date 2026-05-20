with source as (

    select * from {{ source('urbanpulse_silver', 'trips') }}

),

renamed as (

    select
        -- identifiers
        taxi_type,

        -- timestamps
        pickup_datetime,
        dropoff_datetime,
        pickup_hour,
        pickup_day_of_week,

        -- flags
        is_weekend,
        is_rush_hour,

        -- locations
        cast(pulocationid as int) as pickup_location_id,
        pickup_borough,
        pickup_zone,
        cast(dolocationid as int) as dropoff_location_id,
        dropoff_borough,
        dropoff_zone,

        -- trip metrics
        cast(trip_distance     as double) as trip_distance_miles,
        cast(trip_duration_mins as double) as trip_duration_mins,
        cast(passenger_count   as int)    as passenger_count,

        -- financials
        cast(fare_amount  as double) as fare_amount,
        cast(tip_amount   as double) as tip_amount,
        cast(total_amount as double) as total_amount,
        cast(tip_pct      as double) as tip_pct,
        cast(payment_type as int)    as payment_type,

        -- partitions
        year,
        month

    from source

    -- only include records with valid core fields
    where pickup_datetime is not null
      and dropoff_datetime is not null
      and fare_amount > 0
      and trip_distance > 0

)

select * from renamed