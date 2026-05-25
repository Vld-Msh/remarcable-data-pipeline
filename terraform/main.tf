# main.tf — root module; wires together all sub-modules

locals {
  name_prefix = "${var.project}-${var.environment}"
}

# ---------------------------------------------------------------------------
# S3 — three-zone medallion lake (raw / staging / curated)
# ---------------------------------------------------------------------------
module "s3" {
  source = "./modules/s3"

  name_prefix      = local.name_prefix
  environment      = var.environment
  force_destroy    = var.s3_force_destroy
}

# ---------------------------------------------------------------------------
# IAM — roles and policies for Glue, Redshift, Athena, (SageMaker bonus)
# ---------------------------------------------------------------------------
module "iam" {
  source = "./modules/iam"

  name_prefix             = local.name_prefix
  raw_bucket_arn          = module.s3.raw_bucket_arn
  staging_bucket_arn      = module.s3.staging_bucket_arn
  curated_bucket_arn      = module.s3.curated_bucket_arn
  athena_results_bucket_arn = module.s3.athena_results_bucket_arn
  glue_scripts_bucket_arn = module.s3.glue_scripts_bucket_arn
}

# ---------------------------------------------------------------------------
# Glue — crawler + ETL job for raw → staging ingestion
# ---------------------------------------------------------------------------
module "glue" {
  source = "./modules/glue"

  name_prefix          = local.name_prefix
  environment          = var.environment
  glue_role_arn        = module.iam.glue_role_arn
  raw_bucket_name      = module.s3.raw_bucket_name
  staging_bucket_name  = module.s3.staging_bucket_name
  glue_scripts_bucket  = module.s3.glue_scripts_bucket_name
  worker_type          = var.glue_job_worker_type
  num_workers          = var.glue_job_num_workers
  crawler_schedule     = var.glue_crawler_schedule
  log_group_name       = module.cloudwatch.glue_log_group_name
}

# ---------------------------------------------------------------------------
# Redshift Serverless — curated layer query engine
# ---------------------------------------------------------------------------
module "redshift" {
  source = "./modules/redshift"

  name_prefix        = local.name_prefix
  admin_username     = var.redshift_admin_username
  admin_password     = var.redshift_admin_password
  base_capacity      = var.redshift_base_capacity
  subnet_ids         = var.redshift_vpc_subnet_ids
  security_group_ids = var.redshift_vpc_security_group_ids
  redshift_role_arn  = module.iam.redshift_role_arn
  curated_bucket_arn = module.s3.curated_bucket_arn
}

# ---------------------------------------------------------------------------
# Athena — ad-hoc query layer over raw + staging
# ---------------------------------------------------------------------------
module "athena" {
  source = "./modules/athena"

  name_prefix              = local.name_prefix
  athena_results_bucket    = module.s3.athena_results_bucket_name
}

# ---------------------------------------------------------------------------
# CloudWatch — log groups and Glue failure alarm
# ---------------------------------------------------------------------------
module "cloudwatch" {
  source = "./modules/cloudwatch"

  name_prefix        = local.name_prefix
  glue_job_name      = module.glue.glue_job_name
  alarm_email        = var.alarm_email
  log_retention_days = var.log_retention_days
  slack_workspace_id = var.slack_workspace_id
  slack_channel_id   = var.slack_channel_id
}
