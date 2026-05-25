# Assumptions & Trade-offs

This document collects every non-obvious decision made while building this
pipeline so reviewers can evaluate them explicitly rather than reverse-engineer
intent from code.

---

## 1. Data Model

### 1.1 Materialization choices

| Layer | Materialization | Reasoning |
|---|---|---|
| `stg_*` | `view` | Always reflects freshest raw data; no storage cost; staging is cheap to recompute. |
| `dim_contractors` | `table` | Small (≤ 10k rows expected), referenced by every dashboard - table beats view on read latency. |
| `fct_orders` | `incremental` | Grows linearly with order volume; full refresh on every dbt run wastes compute as data scales. Incremental key: `order_id`. |
| `mart_contractor_metrics` | `table` | Aggregation table consumed by BI; recomputed once per dbt run. |

### 1.2 SCD type for `dim_contractors`

Implemented as **SCD Type 1** (overwrite). A contractor moving from `basic` to
`premium` updates the row in place. If retroactive plan-attribution becomes
required (e.g. "what was the contractor's plan when this order was placed?"),
upgrade to SCD Type 2 with `valid_from` / `valid_to` / `is_current` columns -
the rest of the model graph would not change.

### 1.3 `amount_variance` exposed in `fct_orders`

Rather than failing or hiding orders where the header `total_amount` does not
match the sum of line items, the fact table exposes both the absolute
`amount_variance` and a boolean `has_amount_discrepancy` flag. Analysts see DQ
issues directly in the BI tool without running separate DQ jobs.

---

## 2. SaaS Metrics (Part 4)

### 2.1 MRR definition

The dataset is **procurement spend**, not subscription revenue. MRR is computed
as `SUM(total_amount) WHERE status = 'completed'` grouped by month. This is a
proxy, not true SaaS MRR.

In a real environment with a `subscriptions` table, MRR would be:
```sql
SUM(monthly_contract_value) WHERE subscription_status = 'active'
```
The query shape stays identical - only the revenue source changes.

### 2.2 Reference date for "last 30 days"

Hard-coded to **`2024-06-30`** (end of the provided dataset) rather than
`CURRENT_DATE`. Using `CURRENT_DATE` against sample data returns zero rows and
makes the query look broken to reviewers. The constant is defined once at the
top of `analytics/saas_metrics.sql` and is the only thing that needs changing
for production use.

### 2.3 Cancelled orders

Excluded from all revenue, AOV, and retention metrics. Retained in
`fct_orders` with `is_cancelled = true` so cancellation-rate analyses still
work. Mart-layer metrics never silently swallow cancelled rows - the exclusion
is always explicit in the `WHERE` clause.

### 2.4 Retention cohort definition

A contractor's **cohort month** is the month of their first completed order
(not their `contractors.created_at`). A contractor who signs up in January but
places their first order in March is in the March cohort. Rationale: procurement
churn correlates with order behavior, not account creation.

Retention windows are inclusive on both ends - "30-day retention" means at
least one completed order in the 30 days following the cohort start, including
day 0.

---

## 3. Data Quality (Part 3)

### 3.1 Anomaly threshold

Volume-spike detection flags a contractor whose current-week order count
exceeds **3× the trailing 12-week average**, with a minimum baseline of 2
orders/week to avoid noise on low-volume accounts. Configured as a **warning**,
not an error - pipelines do not block on this signal. The 3× factor is a
starting point; in production it should be tuned per-region or per-plan after
observing false-positive rates.

### 3.2 Test severity model

| Severity | Behavior | Examples |
|---|---|---|
| `error` (default) | Blocks downstream dbt models | nulls on PKs, broken referential integrity, negative amounts |
| `warn` | Logs but does not block | anomaly detection, header-vs-line-item variance |

This split prevents soft signals from blocking the entire pipeline while still
making them visible.

### 3.3 `total_amount = SUM(line_items)` tolerance

Comparison uses `ABS(diff) < 0.01` to absorb rounding artifacts from upstream
systems that store unit prices at 4 decimal places but totals at 2.

---

## 4. Infrastructure (Part 2)

### 4.1 Five S3 buckets, not three

The assignment requires `raw`, `staging`, and `curated`. Two extra buckets are
provisioned:
- `athena-results` - Athena requires a dedicated output location; mixing it
  into one of the data buckets pollutes the layer with query artifacts.
- `glue-scripts` - keeps deployable code separate from data so the data
  bucket policy can stay strict (read-only for Glue, etc.).

### 4.2 Alerting

CloudWatch alarms publish to a single SNS topic that fans out to email today.
**Slack via AWS Chatbot is intentionally not provisioned** - it requires a
one-time manual OAuth flow in the AWS Console and a Slack workspace ID that a
reviewer cannot fill in. The SNS topic is the integration point: adding Slack,
PagerDuty, or Opsgenie later is a single subscription resource.

### 4.3 Networking placeholders

`redshift_vpc_subnet_ids` and `redshift_vpc_security_group_ids` default to
placeholder values in `terraform.tfvars`. These must be replaced with real VPC
resources before `terraform apply` succeeds. The placeholders allow
`terraform validate` to pass without requiring a live AWS account.

### 4.4 Secrets handling

`redshift_admin_password` is marked `sensitive = true` and is **never**
written to `terraform.tfvars`. It is supplied via `TF_VAR_redshift_admin_password`
environment variable for this exercise. In production it would live in AWS
Secrets Manager with rotation enabled and be fetched via `data` source - that
swap is local to one module.

### 4.5 Glue job bookmark

Enabled (`job-bookmark-enable`) so reruns process only new files rather than
re-scanning the entire raw bucket. Combined with the daily-trigger schedule,
this keeps incremental ingest cheap.

### 4.6 Athena scan cap

Workgroup configured with a 10 GB per-query scan limit. Stops one bad
`SELECT *` from running up a five-figure bill on a curious analyst.

---

## 5. Bonus - ML / Feature Store (Part 5)

### 5.1 Churn label definition

"Churned" = contractor placed **zero completed orders in the 90 days following
the snapshot date**. This is operational churn, not subscription cancellation
(no subscription table exists). 90-day window chosen to match the longest
retention metric in Part 4.

### 5.2 Point-in-time correctness

Every row in the feature group carries an `event_time` column. Training
joins must use point-in-time semantics (`event_time <= snapshot_date`) to
prevent leakage of future order activity into the feature set.

### 5.3 Feature freshness

- **Offline store**: appended daily by a Glue job running after the main
  staging job completes. Daily granularity is sufficient for batch training.
- **Online store**: updated via a Lambda function triggered on order-status
  changes (EventBridge → Lambda → PutRecord). Enables real-time inference
  on the most recent activity.

---

## 6. Out of scope

The following were considered and deliberately omitted to stay within the
assignment's time envelope:

- **VPC / networking provisioning** - assumes a pre-existing VPC.
- **dbt Cloud / Airflow orchestration** - Glue triggers + cron are sufficient
  for the assignment; production orchestration would layer Airflow or
  Step Functions on top.
- **Real-time CDC ingestion** - the source is daily CSV drops; CDC would
  require a different ingest path (DMS, Kinesis).
- **Cross-region replication** - single region only.
- **Cost estimate** - at expected volumes (~10k orders/month), the dominant
  cost line is Redshift Serverless base capacity ($0.36/RPU-hour × 8 RPU when
  active). All other services are well within the AWS free tier for this
  workload.
