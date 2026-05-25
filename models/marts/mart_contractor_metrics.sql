-- mart_contractor_metrics.sql
-- Wide contractor metrics table for BI/reporting consumption.
-- Combines dim_contractors attributes with order-level aggregations.
-- Grain: one row per contractor_id.
--
-- Metric definitions:
--   total_orders        : count of all orders (completed + cancelled + pending)
--   total_spend         : sum of order_total_amount for completed orders
--   avg_order_value     : total_spend / total_orders (completed orders only)
--   order_frequency_days: avg calendar days between successive completed orders
--                         (null for contractors with 0 or 1 completed orders)

with contractors as (

    select * from {{ ref('dim_contractors') }}

),

orders as (

    select * from {{ ref('fct_orders') }}
    -- all orders included; CASE WHEN filters handle per-metric inclusion

),

-- Calculate inter-order gaps using window function to find order frequency
order_gaps as (

    select
        contractor_id,
        created_date,
        lag(created_date) over (
            partition by contractor_id
            order by created_date
        ) as prev_order_date
    from orders
    where is_completed = true

),

frequency as (

    select
        contractor_id,
        avg(datediff('day', prev_order_date, created_date)) as avg_days_between_orders
    from order_gaps
    where prev_order_date is not null
    group by 1

),

order_agg as (

    select
        contractor_id,

        -- volume
        count(*)                                as total_orders,
        sum(case when is_completed then 1 end)  as completed_orders,
        sum(case when is_cancelled then 1 end)  as cancelled_orders,

        -- spend (completed only)
        sum(case when is_completed then order_total_amount else 0 end) as total_spend,

        -- min/max for range insight
        min(case when is_completed then order_total_amount end)        as min_order_amount,
        max(case when is_completed then order_total_amount end)        as max_order_amount,

        -- date range
        min(created_date)                       as first_order_date,
        max(created_date)                       as last_order_date

    from orders
    group by 1

),

final as (

    select
        -- contractor attributes from dim
        c.contractor_id,
        c.contractor_name,
        c.region,
        c.plan_type,
        c.plan_tier,
        c.contractor_created_date,
        c.days_on_platform,
        c.activity_status,
        c.is_at_churn_risk,

        -- order volume
        coalesce(oa.total_orders,      0)       as total_orders,
        coalesce(oa.completed_orders,  0)       as completed_orders,
        coalesce(oa.cancelled_orders,  0)       as cancelled_orders,

        -- spend metrics
        coalesce(oa.total_spend,       0)       as total_spend,
        oa.min_order_amount,
        oa.max_order_amount,

        -- average order value: null-safe for zero-order contractors
        case
            when coalesce(oa.completed_orders, 0) = 0 then null
            else round(oa.total_spend / oa.completed_orders, 2)
        end                                     as avg_order_value,

        -- order frequency in days (null = fewer than 2 completed orders)
        round(f.avg_days_between_orders, 1)     as avg_days_between_orders,

        -- cancellation rate
        case
            when coalesce(oa.total_orders, 0) = 0 then null
            else round(
                100.0 * coalesce(oa.cancelled_orders, 0) / oa.total_orders,
                1
            )
        end                                     as cancellation_rate_pct,

        -- date range
        oa.first_order_date,
        oa.last_order_date,
        c.days_since_last_order

    from contractors c
    left join order_agg oa  on c.contractor_id = oa.contractor_id
    left join frequency  f  on c.contractor_id = f.contractor_id

)

select * from final
order by total_spend desc
