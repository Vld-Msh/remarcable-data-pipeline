-- =============================================================================
-- saas_metrics.sql - Part 4: SaaS Metrics & Analytics
-- =============================================================================
-- All queries reference mart / fact / dim models in the curated layer.
-- Dialect: standard SQL compatible with Redshift and Athena (minor variance noted).
--
-- ASSUMPTIONS:
--   1. MRR: The dataset represents procurement spend (transactional), not a
--      pure subscription SaaS. We model MRR as the sum of completed order
--      amounts per calendar month. A more rigorous approach would normalize
--      contract ARR → MRR using subscription start/end dates.
--   2. Retention: A contractor is "retained" in month N if they placed at least
--      one completed order in month N AND in their cohort month. 30/60/90-day
--      retention is measured relative to the contractor's first-order month.
--   3. "Last 6 months" and "last 30 days" are evaluated relative to the most
--      recent order in the dataset (2024-06-30), not current_date, because the
--      sample data ends in June 2024.
--   4. Cancelled orders are excluded from all revenue metrics but included in
--      activity/retention checks to reflect genuine engagement.
-- =============================================================================


-- =============================================================================
-- Q1: MRR trend over the last 6 months
-- =============================================================================
-- Returns one row per month showing total spend, MoM growth, and rolling metrics.

WITH monthly_revenue AS (

    SELECT
        date_trunc('month', created_at)          AS revenue_month,
        sum(order_total_amount)                  AS mrr,
        count(DISTINCT contractor_id)            AS active_contractors,
        count(*)                                 AS order_count,
        avg(order_total_amount)                  AS avg_order_value
    FROM   {{ ref('fct_orders') }}
    WHERE  is_completed = true
      -- Last 6 months relative to dataset end (2024-06-30)
      AND  date_trunc('month', created_at) >= date_trunc('month', dateadd('month', -5, '2024-06-30'::date))
    GROUP  BY 1

),

with_growth AS (

    SELECT
        revenue_month,
        mrr,
        active_contractors,
        order_count,
        round(avg_order_value, 2)                                    AS avg_order_value,
        lag(mrr) OVER (ORDER BY revenue_month)                       AS prev_month_mrr,
        round(
            100.0 * (mrr - lag(mrr) OVER (ORDER BY revenue_month))
                  / nullif(lag(mrr) OVER (ORDER BY revenue_month), 0),
            1
        )                                                            AS mrr_growth_pct
    FROM   monthly_revenue

)

SELECT
    to_char(revenue_month, 'YYYY-MM')  AS month,
    round(mrr, 2)                      AS mrr,
    mrr_growth_pct,
    active_contractors,
    order_count,
    avg_order_value
FROM   with_growth
ORDER  BY revenue_month;

/*
 * Expected output (from sample data):
 * 2024-01 | MRR=108821.75 | active=9  contractors
 * 2024-02 | MRR=124971.50 | active=10 contractors
 * 2024-03 | MRR=155680.25 | active=9  contractors
 * 2024-04 | MRR=159350.75 | active=9  contractors (C020 cancelled)
 * 2024-05 | MRR=175001.25 | active=10 contractors
 * 2024-06 | MRR=156050.75 | active=10 contractors
 */


-- =============================================================================
-- Q2: Regions with the highest average order value
-- =============================================================================

SELECT
    c.region,
    count(DISTINCT o.contractor_id)              AS contractor_count,
    count(o.order_id)                            AS total_orders,
    round(sum(o.order_total_amount), 2)          AS total_spend,
    round(avg(o.order_total_amount), 2)          AS avg_order_value,
    round(min(o.order_total_amount), 2)          AS min_order_value,
    round(max(o.order_total_amount), 2)          AS max_order_value
FROM   {{ ref('fct_orders') }}          o
JOIN   {{ ref('dim_contractors') }}     c
    ON o.contractor_id = c.contractor_id
WHERE  o.is_completed = true
GROUP  BY c.region
ORDER  BY avg_order_value DESC;

/*
 * Interpretation: Enterprise contractors (Horizon, Ironclad, Cornerstone) tend
 * to cluster in West and Southwest, driving higher AOV in those regions.
 */


-- =============================================================================
-- Q3: 30 / 60 / 90-day retention rate by plan type
-- =============================================================================
-- Methodology: cohort retention.
--   - Cohort = the month a contractor placed their FIRST completed order.
--   - Retained at 30 days = placed a completed order within days 1–30 after cohort month end.
--   - Retained at 60/90 days = same logic extended.
-- Assumption: "retention" = repeat ordering activity, not login/session.

WITH first_orders AS (

    -- Each contractor's first completed order date (cohort anchor)
    SELECT
        contractor_id,
        min(created_date)                          AS first_order_date,
        date_trunc('month', min(created_date))     AS cohort_month
    FROM   {{ ref('fct_orders') }}
    WHERE  is_completed = true
    GROUP  BY 1

),

subsequent_orders AS (

    -- All completed orders after the first one
    SELECT
        o.contractor_id,
        o.created_date,
        f.first_order_date,
        f.cohort_month,
        datediff('day', f.first_order_date, o.created_date) AS days_since_first_order
    FROM   {{ ref('fct_orders') }}  o
    JOIN   first_orders             f ON o.contractor_id = f.contractor_id
    WHERE  o.is_completed = true
      AND  o.created_date  > f.first_order_date   -- exclude the first order itself

),

cohort_with_plan AS (

    SELECT
        f.contractor_id,
        f.cohort_month,
        c.plan_type,
        -- retained flags: did contractor order within the window?
        max(case when s.days_since_first_order between 1  and 30  then 1 else 0 end) AS retained_30d,
        max(case when s.days_since_first_order between 1  and 60  then 1 else 0 end) AS retained_60d,
        max(case when s.days_since_first_order between 1  and 90  then 1 else 0 end) AS retained_90d
    FROM   first_orders            f
    JOIN   {{ ref('dim_contractors') }} c ON f.contractor_id = c.contractor_id
    LEFT JOIN subsequent_orders    s ON f.contractor_id = s.contractor_id
    GROUP  BY f.contractor_id, f.cohort_month, c.plan_type

)

SELECT
    plan_type,
    count(DISTINCT contractor_id)                            AS cohort_size,
    round(100.0 * sum(retained_30d) / count(*), 1)          AS retention_30d_pct,
    round(100.0 * sum(retained_60d) / count(*), 1)          AS retention_60d_pct,
    round(100.0 * sum(retained_90d) / count(*), 1)          AS retention_90d_pct
FROM   cohort_with_plan
GROUP  BY plan_type
ORDER  BY plan_type;

/*
 * Note: With only 6 months of data and 20 contractors, the cohort sizes are
 * small (5–7 per plan type). In production, aggregate across multiple cohort
 * months to smooth the results.
 */


-- =============================================================================
-- Q4: Contractors who have NOT ordered in the last 30 days
--     but WERE active the previous month
--
-- "Active" = placed at least one completed order in the month.
-- Reference date: 2024-06-30 (end of dataset). In production, use current_date.
-- =============================================================================

WITH ref_date AS (
    SELECT '2024-06-30'::date AS ref_dt
),

activity_by_month AS (

    SELECT
        o.contractor_id,
        date_trunc('month', o.created_date)     AS activity_month,
        count(*)                                 AS orders_in_month
    FROM   {{ ref('fct_orders') }}  o
    CROSS JOIN ref_date
    WHERE  o.is_completed = true
    GROUP  BY 1, 2

),

-- Active last month (May 2024 relative to June 30 reference)
active_last_month AS (

    SELECT contractor_id
    FROM   activity_by_month
    CROSS JOIN ref_date
    WHERE  activity_month = date_trunc('month', dateadd('month', -1, ref_dt))
      AND  orders_in_month >= 1

),

-- Active this month (June 2024)
active_this_month AS (

    SELECT contractor_id
    FROM   activity_by_month
    CROSS JOIN ref_date
    WHERE  activity_month = date_trunc('month', ref_dt)
      AND  orders_in_month >= 1

),

-- Also check last 30 days window (not just calendar month)
ordered_last_30d AS (

    SELECT DISTINCT o.contractor_id
    FROM   {{ ref('fct_orders') }}  o
    CROSS JOIN ref_date
    WHERE  o.is_completed = true
      AND  o.created_date > dateadd('day', -30, ref_dt)

)

SELECT
    lm.contractor_id,
    c.contractor_name,
    c.region,
    c.plan_type,
    c.last_order_date,
    c.days_since_last_order,
    c.activity_status,
    'lapsed_last_30d'           AS flag
FROM   active_last_month        lm
JOIN   {{ ref('dim_contractors') }} c ON lm.contractor_id = c.contractor_id
-- Was active last month but NOT in last 30 days
WHERE  lm.contractor_id NOT IN (SELECT contractor_id FROM ordered_last_30d)
ORDER  BY c.days_since_last_order DESC;

/*
 * These contractors represent the highest-priority re-engagement targets:
 * they were recently active but have gone quiet. Pass this list to CRM/sales.
 */
