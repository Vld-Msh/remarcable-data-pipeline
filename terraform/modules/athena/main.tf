# modules/athena/main.tf
# Athena workgroup for ad-hoc querying of raw and staging zones.

resource "aws_athena_workgroup" "main" {
  name        = "${var.name_prefix}-wg"
  description = "Athena workgroup for ad-hoc queries over raw and staging zones."

  configuration {
    # Enforce query result encryption
    result_configuration {
      output_location = "s3://${var.athena_results_bucket}/query-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    # Cost control: warn at 1 GB, fail at 10 GB per query
    bytes_scanned_cutoff_per_query     = 10737418240   # 10 GB
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
  }

  # Prevent accidental deletion of workgroup with existing queries
  force_destroy = false
}

# Glue catalog is used automatically by Athena; no extra wiring needed.
# Named queries provide saved, reusable SQL for common exploration patterns.
resource "aws_athena_named_query" "sample_orders" {
  name      = "sample-recent-orders"
  workgroup = aws_athena_workgroup.main.id
  database  = "${var.name_prefix}_raw"
  description = "Quick sample of the 100 most recent raw orders."
  query     = <<-SQL
    SELECT *
    FROM   orders
    ORDER  BY created_at DESC
    LIMIT  100;
  SQL
}

resource "aws_athena_named_query" "contractor_spend" {
  name      = "contractor-spend-summary"
  workgroup = aws_athena_workgroup.main.id
  database  = "${var.name_prefix}_raw"
  description = "Total completed spend per contractor from the raw zone."
  query     = <<-SQL
    SELECT
        contractor_id,
        count(*)          AS order_count,
        sum(total_amount) AS total_spend
    FROM   orders
    WHERE  status = 'completed'
    GROUP  BY contractor_id
    ORDER  BY total_spend DESC;
  SQL
}
