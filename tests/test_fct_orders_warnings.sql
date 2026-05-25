{{ config(severity='warn') }}
-- =============================================================================
-- test_fct_orders_warnings.sql
-- Warn-level DQ signals for fct_orders. These return rows in the sample
-- dataset by design (see ASSUMPTIONS.md §1.3 and §3.1) but do NOT block
-- downstream dbt models.
-- =============================================================================

WITH fct AS (SELECT * FROM {{ ref('fct_orders') }})

-- CHECK 1: Header total vs. line-item sum - tolerance $0.01
-- Expected to fire on sample data; surfaced as has_amount_discrepancy in fct_orders.
SELECT order_id AS failing_key, 'amount_discrepancy' AS test_name
FROM   fct
WHERE  is_completed = true
  AND  abs(amount_variance) > 0.01

UNION ALL

-- CHECK 2: Volume spike - contractor order count > 3× trailing 3-month average
-- (see ASSUMPTIONS.md §3.1 for threshold rationale)
SELECT contractor_id, 'volume_spike'
FROM (
    WITH monthly_orders AS (
        SELECT
            contractor_id,
            date_trunc('month', created_at) AS order_month,
            count(*)                        AS order_count
        FROM   fct
        WHERE  is_cancelled = false
        GROUP  BY 1, 2
    ),
    trailing_avg AS (
        SELECT
            contractor_id,
            order_month,
            order_count,
            avg(order_count) OVER (
                PARTITION BY contractor_id
                ORDER BY order_month
                ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
            ) AS trailing_3m_avg,
            sum(order_count) OVER (
                PARTITION BY contractor_id
                ORDER BY order_month
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ) AS historical_total
        FROM   monthly_orders
    )
    SELECT contractor_id
    FROM   trailing_avg
    WHERE  order_month = date_trunc('month', current_timestamp)
      AND  trailing_3m_avg IS NOT NULL
      AND  trailing_3m_avg > 0
      AND  historical_total >= 2
      AND  order_count > (3 * trailing_3m_avg)
) spikes
