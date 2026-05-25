# modules/cloudwatch/main.tf
# CloudWatch log groups and alarms for Glue job monitoring.

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
  period              = 300   # 5 minutes
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# ---------------------------------------------------------------------------
# Additional alarm: Glue job duration > 60 minutes (runaway job detection)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "glue_job_duration" {
  alarm_name          = "${var.name_prefix}-glue-job-duration"
  alarm_description   = "Glue job runtime exceeded 60 minutes — possible runaway job."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "glue.driver.aggregate.elapsedTime"
  namespace           = "Glue"
  period              = 3600   # 1 hour
  statistic           = "Maximum"
  threshold           = 3600000   # 60 min in ms
  treat_missing_data  = "notBreaching"

  dimensions = {
    JobName = var.glue_job_name
    Type    = "gauge"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# ---------------------------------------------------------------------------
# Slack integration via AWS Chatbot
#
# PREREQUISITE (one-time manual step):
#   1. Open the AWS Console → AWS Chatbot → Configure a Slack client
#   2. Authorize the OAuth flow for your Slack workspace
#   3. Copy the Workspace ID shown after authorization into slack_workspace_id
#
# After that, everything below is fully managed by Terraform.
# The existing SNS topic is reused — no duplicate alarm wiring needed.
# ---------------------------------------------------------------------------

# IAM role that Chatbot assumes to publish to SNS and read CloudWatch
data "aws_iam_policy_document" "chatbot_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["chatbot.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "chatbot" {
  name               = "${var.name_prefix}-chatbot-role"
  assume_role_policy = data.aws_iam_policy_document.chatbot_assume.json
}

data "aws_iam_policy_document" "chatbot_policy" {
  statement {
    sid     = "CloudWatchRead"
    actions = [
      "cloudwatch:Describe*",
      "cloudwatch:Get*",
      "cloudwatch:List*",
    ]
    resources = ["*"]
  }
  statement {
    sid     = "SNSPublish"
    actions = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_iam_role_policy" "chatbot" {
  name   = "${var.name_prefix}-chatbot-policy"
  role   = aws_iam_role.chatbot.id
  policy = data.aws_iam_policy_document.chatbot_policy.json
}

# Chatbot Slack channel configuration (requires awscc provider)
resource "awscc_chatbot_slack_channel_configuration" "alerts" {
  configuration_name = "${var.name_prefix}-slack-alerts"
  iam_role_arn       = aws_iam_role.chatbot.arn

  # Populate these via terraform.tfvars — never hardcode workspace/channel IDs
  slack_workspace_id = var.slack_workspace_id
  slack_channel_id   = var.slack_channel_id

  # Reuse the existing SNS topic — alarms already publish here
  sns_topic_arns = [aws_sns_topic.alerts.arn]

  # NONE suppresses the verbose AWS formatting; INFO adds account/region context
  logging_level = "INFO"

  # Guardrails: restrict Chatbot from running any AWS CLI commands from Slack
  guardrail_policies = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
}
