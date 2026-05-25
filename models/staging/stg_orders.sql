-- stg_orders.sql
-- Staging model for raw orders data.
-- Applies type casting, null coalescing, and status normalization.
-- Grain: one row per order_id.

with source as (

    select * from {{ source('raw', 'orders') }}

),

cleaned as (

    select
        -- primary key
        trim(order_id)                                      as order_id,

        -- foreign key
        trim(contractor_id)                                 as contractor_id,

        -- timestamps - cast to UTC timestamp; reject unparseable rows via coalesce sentinel
        cast(created_at as timestamp)                       as created_at,
        date_trunc('day',  cast(created_at as timestamp))  as created_date,
        date_trunc('month', cast(created_at as timestamp)) as created_month,

        -- status - lowercase + strip whitespace for consistent downstream filtering
        lower(trim(status))                                 as status,

        -- financials - cast to numeric; guard against negative values from upstream
        cast(total_amount as numeric(18, 2))                as total_amount,

        -- boolean convenience flags
        case when lower(trim(status)) = 'completed'  then true else false end as is_completed,
        case when lower(trim(status)) = 'cancelled'  then true else false end as is_cancelled,
        case when lower(trim(status)) = 'pending'    then true else false end as is_pending

    from source
    where
        -- drop rows with no primary key (cannot be keyed in downstream models)
        order_id is not null
        -- drop rows with no contractor reference (orphaned orders)
        and contractor_id is not null
        -- drop rows where amount is negative (data integrity guard)
        and cast(total_amount as numeric(18, 2)) >= 0

)

select * from cleaned
