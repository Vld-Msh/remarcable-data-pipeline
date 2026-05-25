-- =============================================================================
-- test_fct_orders.sql
-- Data quality checks for the fct_orders model.
-- Convention: each test is a SELECT that returns rows ONLY when the check fails.
-- A passing test returns zero rows. Run all checks with:
--   SELECT * FROM <test_name>  -- expect: 0 rows returned
-- In dbt, these are written as singular tests (tests/*.sql).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TEST 1: Primary key uniqueness — every order_id must be unique
-- -----------------------------------------------------------------------------
-- dbt equivalent: unique test on order_id column (in schema.yml)
SELECT
    order_id,
    count(*) AS duplicate_count
FROM   {{ ref('fct_orders') }}
GROUP  BY order_id
HAVING count(*) > 1;
-- Expected: 0 rows

-- -----------------------------------------------------------------------------
-- TEST 2: No null primary keys
-- -----------------------------------------------------------------------------
-- dbt equivalent: not_null test on order_id column
SELECT order_id
FROM   {{ ref('fct_orders') }}
WHERE  order_id IS NULL;
-- Expected: 0 rows

-- -----------------------------------------------------------------------------
-- TEST 3: No null contractor_id (referential integrity pre-check)
-- -----------------------------------------------------------------------------
SELECT order_id
FROM   {{ ref('fct_orders') }}
WHERE  contractor_id IS NULL;
-- Expected: 0 rows

-- -----------------------------------------------------------------------------
-- TEST 4: Referential integrity — every contractor_id in fct_orders must
--         exist in dim_contractors
-- -----------------------------------------------------------------------------
-- dbt equivalent: relationships test
SELECT
    o.order_id,
    o.contractor_id
FROM   {{ ref('fct_orders') }}      o
LEFT JOIN {{ ref('dim_contractors') }} c
    ON o.contractor_id = c.contractor_id
WHERE  c.contractor_id IS NULL;
-- Expected: 0 rows

-- -----------------------------------------------------------------------------
-- TEST 5: No null created_at
-- -----------------------------------------------------------------------------
SELECT order_id
FROM   {{ ref('fct_orders') }}
WHERE  created_at IS NULL;
-- Expected: 0 rows

-- -----------------------------------------------------------------------------
-- TEST 6: Status must be in allowed set
-- -----------------------------------------------------------------------------
-- dbt equivalent: accepted_values test
SELECT
    order_id,
    status
FROM   {{ ref('fct_orders') }}
WHERE  status NOT IN ('completed', 'cancelled', 'pending');
-- Expected: 0 rows

-- -----------------------------------------------------------------------------
-- TEST 7: order_total_amount must be non-negative
-- -----------------------------------------------------------------------------
SELECT
    order_id,
    order_total_amount
FROM   {{ ref('fct_orders') }}
WHERE  order_total_amount < 0;
-- Expected: 0 rows

-- -----------------------------------------------------------------------------
-- TEST 8: Business logic — order_total_amount should match sum of line items
--         Tolerance: $0.01 for floating-point rounding.
--         Only applies to completed orders (cancelled orders may have partial items).
-- -----------------------------------------------------------------------------
SELECT
    order_id,
    order_total_amount,
    calculated_total_amount,
    amount_variance
FROM   {{ ref('fct_orders') }}
WHERE  is_completed = true
  AND  abs(amount_variance) > 0.01;
-- Expected: 0 rows (a non-zero result means header vs. line item mismatch)

-- -----------------------------------------------------------------------------
-- TEST 9: Completed orders must have at least one line item
-- -----------------------------------------------------------------------------
SELECT
    order_id,
    line_item_count
FROM   {{ ref('fct_orders') }}
WHERE  is_completed = true
  AND  line_item_count = 0;
-- Expected: 0 rows

-- -----------------------------------------------------------------------------
-- TEST 10: No future-dated orders (created_at cannot be after today)
-- -----------------------------------------------------------------------------
SELECT
    order_id,
    created_at
FROM   {{ ref('fct_orders') }}
WHERE  created_at > current_timestamp;
-- Expected: 0 rows

-- -----------------------------------------------------------------------------
-- TEST 11: No negative line_item_count or total_units
-- -----------------------------------------------------------------------------
SELECT order_id, line_item_count, total_units
FROM   {{ ref('fct_orders') }}
WHERE  line_item_count < 0
    OR total_units < 0;
-- Expected: 0 rows

-- -----------------------------------------------------------------------------
-- TEST 12: Anomaly detection — contractors with a sudden spike in order volume
--
-- Logic: compare each contractor's order count in the current month vs.
-- their trailing 3-month average. Flag if current month is > 3× the average
-- AND the contractor placed at least 2 orders historically (to avoid
-- false-positives on new contractors).
--
-- Returns rows for contractors whose activity should be reviewed.
-- This is a WARNING, not necessarily a data error.
-- -----------------------------------------------------------------------------
WITH monthly_orders AS (

    SELECT
        contractor_id,
        date_trunc('month', created_at)  AS order_month,
        count(*)                         AS order_count
    FROM   {{ ref('fct_orders') }}
    WHERE  is_cancelled = false
    GROUP  BY 1, 2

),

trailing_avg AS (

    SELECT
        contractor_id,
        order_month,
        order_count,
        -- 3-month trailing average EXCLUDING the current month
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

),

current_month AS (

    SELECT *
    FROM   trailing_avg
    WHERE  order_month = date_trunc('month', current_timestamp)

)

SELECT
    contractor_id,
    order_month,
    order_count                          AS current_month_orders,
    trailing_3m_avg,
    round(order_count / trailing_3m_avg, 2) AS spike_ratio,
    'volume_spike'                       AS anomaly_type
FROM   current_month
WHERE  trailing_3m_avg IS NOT NULL
  AND  trailing_3m_avg > 0
  AND  historical_total >= 2                    -- exclude contractors with thin history
  AND  order_count > (3 * trailing_3m_avg);     -- >3× trailing average = spike
-- Expected: 0 rows in steady-state; any rows warrant investigation
