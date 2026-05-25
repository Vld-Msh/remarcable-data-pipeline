"""
raw_to_staging.py — AWS Glue ETL job
Reads raw CSV files from S3 (catalogued by Glue crawler), applies cleaning /
type casting, and writes Parquet-partitioned output to the staging zone.

Deploy: upload this script to s3://<glue-scripts-bucket>/scripts/raw_to_staging.py

Environment routing:
  Pass --ENV dev  → reads remarcable-dev-raw,  writes remarcable-dev-staging
  Pass --ENV prod → reads remarcable-prod-raw, writes remarcable-prod-staging
  Defaults to 'dev' if omitted (safe default — never accidentally write to prod).
"""

import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame
from pyspark.sql import functions as F
from pyspark.sql.types import (
    DecimalType, IntegerType, TimestampType, StringType, DateType
)

# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------
args = getResolvedOptions(sys.argv, [
    "JOB_NAME",
    "ENV",           # 'dev' or 'prod' — injected by Terraform default_arguments
])

# ---------------------------------------------------------------------------
# Environment config — mirrors the naming convention used across DE repos.
# All resource names are derived from this single dict; no scattered if/elif.
# ---------------------------------------------------------------------------
VALID_ENVS = ("dev", "prod")
env = args.get("ENV", "dev").lower()
if env not in VALID_ENVS:
    raise ValueError(f"Invalid ENV '{env}'. Must be one of {VALID_ENVS}.")

ENV_CONFIG = {
    "prod": {
        "raw_bucket":     "remarcable-prod-raw",
        "staging_bucket": "remarcable-prod-staging",
        "raw_db":         "remarcable_prod_raw",
        "staging_db":     "remarcable_prod_staging",
    },
    "dev": {
        "raw_bucket":     "remarcable-dev-raw",
        "staging_bucket": "remarcable-dev-staging",
        "raw_db":         "remarcable_dev_raw",
        "staging_db":     "remarcable_dev_staging",
    },
}

config = ENV_CONFIG[env]
RAW_BUCKET     = config["raw_bucket"]
STAGING_BUCKET = config["staging_bucket"]
SOURCE_DB      = config["raw_db"]

print(f"[ENV={env}] RAW_BUCKET={RAW_BUCKET} | STAGING_BUCKET={STAGING_BUCKET} | SOURCE_DB={SOURCE_DB}")

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

# ---------------------------------------------------------------------------
# Helper: write as Parquet to staging zone with job-bookmark support
# ---------------------------------------------------------------------------
def write_staging(df, table_name: str, partition_cols: list = None):
    dyf = DynamicFrame.fromDF(df, glueContext, table_name)
    sink_opts = {
        "path": f"s3://{STAGING_BUCKET}/{table_name}/",
        "compression": "snappy",
    }
    if partition_cols:
        sink_opts["partitionKeys"] = partition_cols

    glueContext.write_dynamic_frame.from_options(
        frame=dyf,
        connection_type="s3",
        format="glueparquet",
        connection_options=sink_opts,
        format_options={"compression": "snappy"},
    )

# ---------------------------------------------------------------------------
# 1. orders
# ---------------------------------------------------------------------------
orders_raw = glueContext.create_dynamic_frame.from_catalog(
    database=SOURCE_DB,
    table_name="orders",
    transformation_ctx="orders_raw",
)

orders_df = orders_raw.toDF()
orders_clean = (
    orders_df
    .filter(F.col("order_id").isNotNull())
    .filter(F.col("contractor_id").isNotNull())
    .withColumn("order_id",      F.trim(F.col("order_id")))
    .withColumn("contractor_id", F.trim(F.col("contractor_id")))
    .withColumn("status",        F.lower(F.trim(F.col("status"))))
    .withColumn("created_at",    F.to_timestamp(F.col("created_at"), "yyyy-MM-dd HH:mm:ss"))
    .withColumn("created_date",  F.to_date(F.col("created_at")))
    .withColumn("created_month", F.date_trunc("month", F.col("created_at")))
    .withColumn("total_amount",  F.col("total_amount").cast(DecimalType(18, 2)))
    .withColumn("is_completed",  F.col("status") == F.lit("completed"))
    .withColumn("is_cancelled",  F.col("status") == F.lit("cancelled"))
    .withColumn("is_pending",    F.col("status") == F.lit("pending"))
    # Add load metadata for freshness checks
    .withColumn("_glue_loaded_at", F.current_timestamp())
    .filter(F.col("total_amount") >= 0)
)

write_staging(orders_clean, "orders", partition_cols=["created_month"])

# ---------------------------------------------------------------------------
# 2. contractors
# ---------------------------------------------------------------------------
contractors_raw = glueContext.create_dynamic_frame.from_catalog(
    database=SOURCE_DB,
    table_name="contractors",
    transformation_ctx="contractors_raw",
)

contractors_df = contractors_raw.toDF()
contractors_clean = (
    contractors_df
    .filter(F.col("contractor_id").isNotNull())
    .filter(F.col("name").isNotNull())
    .withColumn("contractor_id",   F.trim(F.col("contractor_id")))
    .withColumn("name",            F.trim(F.col("name")))
    .withColumn("region",          F.lower(F.trim(F.col("region"))))
    .withColumn("plan_type",       F.lower(F.trim(F.col("plan_type"))))
    .withColumn("created_at",      F.to_date(F.col("created_at")))
    .withColumn("plan_tier", F.when(F.col("plan_type") == "starter",      1)
                               .when(F.col("plan_type") == "professional", 2)
                               .when(F.col("plan_type") == "enterprise",   3)
                               .otherwise(0))
    .withColumn("_glue_loaded_at", F.current_timestamp())
)

write_staging(contractors_clean, "contractors")

# ---------------------------------------------------------------------------
# 3. order_items
# ---------------------------------------------------------------------------
items_raw = glueContext.create_dynamic_frame.from_catalog(
    database=SOURCE_DB,
    table_name="order_items",
    transformation_ctx="order_items_raw",
)

items_df = items_raw.toDF()
items_clean = (
    items_df
    .filter(F.col("item_id").isNotNull())
    .filter(F.col("order_id").isNotNull())
    .withColumn("item_id",     F.trim(F.col("item_id")))
    .withColumn("order_id",    F.trim(F.col("order_id")))
    .withColumn("product_id",  F.trim(F.col("product_id")))
    .withColumn("quantity",    F.col("quantity").cast(IntegerType()))
    .withColumn("unit_price",  F.col("unit_price").cast(DecimalType(18, 2)))
    .withColumn("line_amount", F.col("quantity") * F.col("unit_price"))
    .filter(F.col("quantity")   > 0)
    .filter(F.col("unit_price") > 0)
    .withColumn("_glue_loaded_at", F.current_timestamp())
)

write_staging(items_clean, "order_items")

# ---------------------------------------------------------------------------
# Commit job bookmark so incremental runs only process new data
# ---------------------------------------------------------------------------
job.commit()
