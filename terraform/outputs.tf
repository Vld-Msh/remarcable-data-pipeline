# outputs.tf — exposes key ARNs and endpoints for downstream use

# ---------------------------------------------------------------------------
# S3
# ---------------------------------------------------------------------------
output "raw_bucket_name" {
  description = "Name of the raw S3 bucket."
  value       = module.s3.raw_bucket_name
}

output "raw_bucket_arn" {
  description = "ARN of the raw S3 bucket."
  value       = module.s3.raw_bucket_arn
}

output "staging_bucket_name" {
  description = "Name of the staging S3 bucket."
  value       = module.s3.staging_bucket_name
}

output "curated_bucket_name" {
  description = "Name of the curated S3 bucket."
  value       = module.s3.curated_bucket_name
}

output "athena_results_bucket_name" {
  description = "Name of the Athena query-results S3 bucket."
  value       = module.s3.athena_results_bucket_name
}

# ---------------------------------------------------------------------------
# IAM
# ---------------------------------------------------------------------------
output "glue_role_arn" {
  description = "ARN of the IAM role used by Glue."
  value       = module.iam.glue_role_arn
}

output "redshift_role_arn" {
  description = "ARN of the IAM role used by Redshift Serverless."
  value       = module.iam.redshift_role_arn
}

output "athena_role_arn" {
  description = "ARN of the IAM role used by Athena."
  value       = module.iam.athena_role_arn
}

# ---------------------------------------------------------------------------
# Glue
# ---------------------------------------------------------------------------
output "glue_database_name" {
  description = "Name of the Glue Data Catalog database."
  value       = module.glue.glue_database_name
}

output "glue_crawler_name" {
  description = "Name of the Glue crawler."
  value       = module.glue.glue_crawler_name
}

output "glue_job_name" {
  description = "Name of the Glue ETL job."
  value       = module.glue.glue_job_name
}

# ---------------------------------------------------------------------------
# Redshift Serverless
# ---------------------------------------------------------------------------
output "redshift_namespace_arn" {
  description = "ARN of the Redshift Serverless namespace."
  value       = module.redshift.namespace_arn
}

output "redshift_workgroup_endpoint" {
  description = "JDBC endpoint for the Redshift Serverless workgroup."
  value       = module.redshift.workgroup_endpoint
}

# ---------------------------------------------------------------------------
# Athena
# ---------------------------------------------------------------------------
output "athena_workgroup_name" {
  description = "Name of the Athena workgroup."
  value       = module.athena.workgroup_name
}

# ---------------------------------------------------------------------------
# CloudWatch
# ---------------------------------------------------------------------------
output "glue_log_group_name" {
  description = "CloudWatch log group for Glue job output."
  value       = module.cloudwatch.glue_log_group_name
}

output "glue_failure_alarm_arn" {
  description = "ARN of the CloudWatch alarm for Glue job failures."
  value       = module.cloudwatch.glue_failure_alarm_arn
}

output "alerts_sns_topic_arn" {
  description = "SNS topic ARN that broadcasts pipeline alerts (email today; extendable to Slack/PagerDuty)."
  value       = module.cloudwatch.alerts_sns_topic_arn
}
