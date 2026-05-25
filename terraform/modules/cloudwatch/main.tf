# modules/cloudwatch/main.tf
# CloudWatch log groups and alarms for Glue job monitoring.
# Notifications routed through SNS → email per the assignment spec.
# Slack routing via AWS Chatbot is described as a future enhancement in the
# root README — not provisioned here to keep the module self-contained and
# reviewable without out-of-band Slack OAuth setup.

# ---------------------------------------------------------------------------
# Log Groups
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "glue" {
  name              = "/aws/glue/${var.name_prefix}"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "glue_spark" {
  name              = "/aws/glue/${var.name_prefix}/spark"
  retention_in_days = var.log_retention_days
}

# ---------------------------------------------------------------------------
# SNS Topic for alarm notifications
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-data-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ---------------------------------------------------------------------------
# Metric Filter — detect Glue job failures from CloudWatch logs
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_metric_filter" "glue_failure" {
  name           = "${var.name_prefix}-glue-job-failure"
  pattern        = "\"Job failed\""
  log_group_name = aws_cloudwatch_log_group.glue.name

  metric_transformation {
    name      = "GlueJobFailureCount"
    namespace = "Remarcable/Glue"
    value     = "1"
    unit      = "Count"
  }
}

# ---------------------------------------------------------------------------
# CloudWatch Alarm — fires when ≥1 Glue failure in a 5-minute window
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "glue_job_failure" {
  alarm_name          = "${var.name_prefix}-glue-job-failure"
  alarm_description   = "Fires when the Glue ETL job fails. Check CloudWatch logs for root cause."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "GlueJobFailureCount"
  namespace           = "Remarcable/Glue"
  period              = 300 # 5 minutes
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# ---------------------------------------------------------------------------
# Additional alarm: Glue job duration > 60 minutes (runaway job detection).
# The failure-pattern alarm above only catches crashes; long-running jobs that
# never error out would otherwise go unnoticed.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "glue_job_duration" {
  alarm_name          = "${var.name_prefix}-glue-job-duration"
  alarm_description   = "Glue job runtime exceeded 60 minutes — possible runaway job."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "glue.driver.aggregate.elapsedTime"
  namespace           = "Glue"
  period              = 3600    # 1 hour
  statistic           = "Maximum"
  threshold           = 3600000 # 60 min in ms
  treat_missing_data  = "notBreaching"

  dimensions = {
    JobName = var.glue_job_name
    Type    = "gauge"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}
