# bonus/sagemaker_terraform.tf
# Terraform resources for SageMaker churn model training + feature store access.
# These resources complement the IAM SageMaker role already defined in modules/iam.

# ---------------------------------------------------------------------------
# S3 bucket for SageMaker artifacts (model checkpoints, training data, output)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "sagemaker" {
  bucket        = "${var.name_prefix}-sagemaker-artifacts"
  force_destroy = false   # never auto-delete model artifacts in prod
}

resource "aws_s3_bucket_versioning" "sagemaker" {
  bucket = aws_s3_bucket.sagemaker.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sagemaker" {
  bucket = aws_s3_bucket.sagemaker.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "sagemaker" {
  bucket                  = aws_s3_bucket.sagemaker.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle: move old model artifacts to Glacier after 180 days
resource "aws_s3_bucket_lifecycle_configuration" "sagemaker" {
  bucket = aws_s3_bucket.sagemaker.id
  rule {
    id     = "archive-old-models"
    status = "Enabled"
    filter { prefix = "models/" }
    transition {
      days          = 180
      storage_class = "GLACIER"
    }
  }
}

# ---------------------------------------------------------------------------
# SageMaker Feature Group — contractor_churn_features
# Backed by the curated S3 bucket (offline store) and DynamoDB (online store).
# ---------------------------------------------------------------------------
resource "aws_sagemaker_feature_group" "contractor_churn" {
  feature_group_name             = "${var.name_prefix}-contractor-churn-features"
  record_identifier_feature_name = "record_id"
  event_time_feature_name        = "event_time"
  role_arn                       = module.iam.sagemaker_role_arn

  # Offline store: S3-backed, queryable via Athena
  offline_store_config {
    s3_storage_config {
      s3_uri = "s3://${module.s3.curated_bucket_name}/feature-store/contractor-churn/"
    }
    disable_glue_table_creation = false   # auto-register in Glue Data Catalog
  }

  # Online store: low-latency reads for real-time inference
  online_store_config {
    enable_online_store = true
  }

  # Feature definitions — must match feature_store.sql schema
  feature_definition { feature_name = "record_id";                    feature_type = "String" }
  feature_definition { feature_name = "event_time";                   feature_type = "String" }
  feature_definition { feature_name = "plan_type";                    feature_type = "String" }
  feature_definition { feature_name = "plan_tier";                    feature_type = "Integral" }
  feature_definition { feature_name = "region";                       feature_type = "String" }
  feature_definition { feature_name = "days_on_platform";             feature_type = "Integral" }
  feature_definition { feature_name = "months_on_platform";           feature_type = "Integral" }
  feature_definition { feature_name = "days_since_last_order";        feature_type = "Integral" }
  feature_definition { feature_name = "orders_l30d";                  feature_type = "Integral" }
  feature_definition { feature_name = "orders_l60d";                  feature_type = "Integral" }
  feature_definition { feature_name = "orders_l90d";                  feature_type = "Integral" }
  feature_definition { feature_name = "orders_lifetime";              feature_type = "Integral" }
  feature_definition { feature_name = "spend_l30d";                   feature_type = "Fractional" }
  feature_definition { feature_name = "spend_l90d";                   feature_type = "Fractional" }
  feature_definition { feature_name = "spend_lifetime";               feature_type = "Fractional" }
  feature_definition { feature_name = "avg_order_value_lifetime";     feature_type = "Fractional" }
  feature_definition { feature_name = "cancelled_orders_lifetime";    feature_type = "Integral" }
  feature_definition { feature_name = "cancellation_rate_pct";        feature_type = "Fractional" }
  feature_definition { feature_name = "order_count_mom_delta";        feature_type = "Integral" }
  feature_definition { feature_name = "spend_mom_delta";              feature_type = "Fractional" }
  feature_definition { feature_name = "avg_days_between_orders";      feature_type = "Fractional" }
  feature_definition { feature_name = "stddev_days_between_orders";   feature_type = "Fractional" }
  feature_definition { feature_name = "orders_l30d_share";            feature_type = "Fractional" }
  feature_definition { feature_name = "spend_l90d_share";             feature_type = "Fractional" }

  tags = {
    Component   = "ml-feature-store"
    Model       = "contractor-churn"
    Environment = var.environment
    Project     = var.project
    Owner       = var.owner
    ManagedBy   = "terraform"
  }
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
output "sagemaker_bucket_name" {
  description = "S3 bucket for SageMaker model artifacts."
  value       = aws_s3_bucket.sagemaker.bucket
}

output "sagemaker_feature_group_arn" {
  description = "ARN of the SageMaker Feature Group for contractor churn."
  value       = aws_sagemaker_feature_group.contractor_churn.arn
}
