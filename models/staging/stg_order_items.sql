-- stg_order_items.sql
-- Staging model for raw order_items data.
-- Casts types, derives line-item totals, guards against zero/negative quantities.
-- Grain: one row per item_id.

with source as (

    select * from {{ source('raw', 'order_items') }}

),

cleaned as (

    select
        -- primary key
        trim(item_id)                                           as item_id,

        -- foreign keys
        trim(order_id)                                          as order_id,
        trim(product_id)                                        as product_id,

        -- measures — cast to appropriate numeric types
        cast(quantity   as integer)                             as quantity,
        cast(unit_price as numeric(18, 2))                      as unit_price,

        -- derived: line-item extended amount
        cast(quantity as integer) * cast(unit_price as numeric(18, 2)) as line_amount

    from source
    where
        item_id    is not null
        and order_id   is not null
        and product_id is not null
        -- guard: no zero or negative quantities
        and cast(quantity as integer) > 0
        -- guard: no zero or negative prices
        and cast(unit_price as numeric(18, 2)) > 0

)

select * from cleaned
