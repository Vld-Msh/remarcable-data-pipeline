-- fct_orders.sql
-- Fact table for purchase orders.
-- Joins orders with aggregated line-item totals and enriches with contractor dimension key.
-- Grain: one row per order_id.
-- Only includes non-cancelled orders by default; use the is_cancelled flag to include them.

with orders as (

    select * from {{ ref('stg_orders') }}

),

order_item_totals as (

    -- Roll up line items to order level so fct_orders carries both the header amount
    -- and the sum-of-lines amount — the delta surfaces data quality issues.
    select
        order_id,
        count(*)            as line_item_count,
        sum(quantity)       as total_units,
        sum(line_amount)    as calculated_total_amount
    from {{ ref('stg_order_items') }}
    group by 1

),

final as (

    select
        -- surrogate key (use order_id directly; no compound PK needed here)
        o.order_id,

        -- foreign keys
        o.contractor_id,

        -- dates
        o.created_at,
        o.created_date,
        o.created_month,

        -- order status
        o.status,
        o.is_completed,
        o.is_cancelled,
        o.is_pending,

        -- financials from order header
        o.total_amount                                                                       as order_total_amount,

        -- financials computed from line items
        coalesce(oit.calculated_total_amount, 0)                                            as calculated_total_amount,

        -- delta: positive means header > lines (possible data issue)
        o.total_amount - coalesce(oit.calculated_total_amount, 0)                           as amount_variance,

        -- flag orders where header and lines differ by more than $0.01 (rounding tolerance)
        case
            when abs(o.total_amount - coalesce(oit.calculated_total_amount, 0)) > 0.01
            then true
            else false
        end                                                                                  as has_amount_discrepancy,

        -- line item counts
        coalesce(oit.line_item_count, 0)                                                    as line_item_count,
        coalesce(oit.total_units, 0)                                                        as total_units

    from orders o
    left join order_item_totals oit
        on o.order_id = oit.order_id

)

select * from final
