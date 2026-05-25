-- dim_contractors.sql
-- Dimension table for contractors.
-- Enriches staging data with first/last order dates pulled from fct_orders
-- so consumers have a single denormalized lookup for all contractor attributes.
-- Grain: one row per contractor_id (SCD Type 1 — overwrites on refresh).

with contractors as (

    select * from {{ ref('stg_contractors') }}

),

order_activity as (

    -- Aggregate completed-order activity per contractor for enrichment columns.
    -- Cancelled orders are excluded to reflect true transactional engagement.
    select
        contractor_id,
        min(created_date)                           as first_order_date,
        max(created_date)                           as last_order_date,
        count(*)                                    as lifetime_order_count,
        sum(order_total_amount)                     as lifetime_spend,
        datediff('day', max(created_date), current_date) as days_since_last_order
    from {{ ref('fct_orders') }}
    where is_completed = true
    group by 1

),

final as (

    select
        -- primary key
        c.contractor_id,

        -- descriptive attributes
        c.contractor_name,
        c.region,
        c.plan_type,
        c.plan_tier,

        -- tenure
        c.created_date                                  as contractor_created_date,
        c.days_on_platform,

        -- activity attributes (null when contractor has never ordered)
        oa.first_order_date,
        oa.last_order_date,
        oa.lifetime_order_count,
        oa.lifetime_spend,
        oa.days_since_last_order,

        -- churn risk flag: no completed order in last 60 days
        case
            when oa.days_since_last_order > 60 or oa.last_order_date is null
            then true
            else false
        end                                             as is_at_churn_risk,

        -- activity status
        case
            when oa.last_order_date is null             then 'never_ordered'
            when oa.days_since_last_order <= 30         then 'active'
            when oa.days_since_last_order <= 90         then 'at_risk'
            else                                             'churned'
        end                                             as activity_status

    from contractors c
    left join order_activity oa
        on c.contractor_id = oa.contractor_id

)

select * from final
