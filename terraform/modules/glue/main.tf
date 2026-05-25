# modules/glue/main.tf
# Glue Data Catalog database, crawler (raw zone), and ETL job (raw → staging).

# ---------------------------------------------------------------------------
# Glue Data Catalog - one database per zone for namespace isolation
# ---------------------------------------------------------------------------
resource "aws_glue_catalog_database" "raw" {
  name        = "${var.name_prefix}_raw"
  description = "Glue Data Catalog for the raw zone - auto-populated by crawler."
}

resource "aws_glue_catalog_database" "staging" {
  name        = "${var.name_prefix}_staging"
  description = "Glue Data Catalog for the staging zone - populated by ETL job."
}

# ---------------------------------------------------------------------------
# Glue Crawler - catalogs raw CSV data from S3
# ---------------------------------------------------------------------------
resource "aws_glue_crawler" "raw" {
  name          = "${var.name_prefix}-raw-crawler"
  role          = var.glue_role_arn
  database_name = aws_glue_catalog_database.raw.name
  description   = "Crawls the raw S3 zone to infer schema and update the Glue Data Catalog."

  s3_target {
    path = "s3://${var.raw_bucket_name}/"
  }

  # Re-crawl only changed files to reduce cost and runtime
  recrawl_policy {
    recrawl_behavior = "CRAWL_NEW_FOLDERS_ONLY"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  # Optional scheduled trigger (empty string = on-demand only)
  schedule = var.crawler_schedule != "" ? var.crawler_schedule : null

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
      Tables     = { AddOrUpdateBehavior = "MergeNewColumns" }
    }
  })
}

# ---------------------------------------------------------------------------
# Glue ETL Job - raw (CSV) → staging (Parquet + type casts)
# ---------------------------------------------------------------------------
resource "aws_glue_job" "raw_to_staging" {
  name        = "${var.name_prefix}-raw-to-staging"
  role_arn    = var.glue_role_arn
  description = "Reads CSV files from the raw zone, applies type casting and cleaning, writes Parquet to staging."

  command {
    name            = "glueetl"
    script_location = "s3://${var.glue_scripts_bucket}/scripts/raw_to_staging.py"
    python_version  = "3"
  }

  glue_version      = "4.0"
  worker_type       = var.worker_type
  number_of_workers = var.num_workers

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-enable"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"                   = ""
    "--enable-spark-ui"                  = "true"
    "--spark-event-logs-path"            = "s3://${var.glue_scripts_bucket}/spark-logs/"
    "--TempDir"                          = "s3://${var.glue_scripts_bucket}/tmp/"
    "--continuous-log-logGroup"          = var.log_group_name
    # Environment routing - the script derives all resource names from this single arg.
    # Terraform passes var.environment ('dev' or 'prod') set in terraform.tfvars.
    "--ENV" = var.environment
  }

  execution_property {
    max_concurrent_runs = 1
  }

  tags = {
    Component = "glue-etl"
  }
}

# ---------------------------------------------------------------------------
# Glue Trigger - daily scheduled run after crawler completes
# ---------------------------------------------------------------------------
resource "aws_glue_trigger" "daily_etl" {
  name     = "${var.name_prefix}-daily-etl-trigger"
  type     = "SCHEDULED"
  schedule = "cron(30 6 * * ? *)" # 06:30 UTC - 30 min after crawler

  actions {
    job_name = aws_glue_job.raw_to_staging.name
  }
}
