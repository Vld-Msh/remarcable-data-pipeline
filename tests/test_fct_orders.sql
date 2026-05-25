-- =============================================================================
-- test_fct_orders.sql
-- Hard-failure data quality checks for fct_orders.
-- Each check returns 0 rows when passing; any row is a pipeline-blocking error.
-- Warn-level checks (amount_discrepancy, volume_spike) are in
-- test_fct_orders_warnings.sql.
-- =============================================================================

WITH fct AS (SELECT * FROM {{ ref('fct_orders') }}),
     dim AS (SELECT contractor_id FROM {{ ref('dim_contractors') }})

-- TEST 1: Primary key uniqueness
SELECT order_id AS failing_key, 'duplicate_order_id' AS test_name
FROM   fct
GROUP  BY order_id
HAVING count(*) > 1

UNION ALL

-- TEST 2: No null primary keys
SELECT order_id, 'null_order_id'
FROM   fct
WHERE  order_id IS NULL

UNION ALL

-- TEST 3: No null contractor_id
SELECT order_id, 'null_contractor_id'
FROM   fct
WHERE  contractor_id IS NULL

UNION ALL

-- TEST 4: Referential integrity – every contractor_id must exist in dim_contractors
SELECT o.order_id, 'missing_contractor_in_dim'
FROM   fct o
LEFT JOIN dim c ON o.contractor_id = c.contractor_id
WHERE  c.contractor_id IS NULL

UNION ALL

-- TEST 5: No null created_at
SELECT order_id, 'null_created_at'
FROM   fct
WHERE  created_at IS NULL

UNION ALL

-- TEST 6: Status must be in allowed set
SELECT order_id, 'invalid_status'
FROM   fct
WHERE  status NOT IN ('completed', 'cancelled', 'pending')

UNION ALL

-- TEST 7: order_total_amount must be non-negative
SELECT order_id, 'negative_order_total'
FROM   fct
WHERE  order_total_amount < 0

UNION ALL

-- TEST 8: Completed orders must have at least one line item
SELECT order_id, 'completed_order_no_line_items'
FROM   fct
WHERE  is_completed = true
  AND  line_item_count = 0

UNION ALL

-- TEST 9: No future-dated orders
SELECT order_id, 'future_dated_order'
FROM   fct
WHERE  created_at > current_timestamp

UNION ALL

-- TEST 10: No negative line_item_count or total_units
SELECT order_id, 'negative_counts'
FROM   fct
WHERE  line_item_count < 0
    OR total_units < 0
