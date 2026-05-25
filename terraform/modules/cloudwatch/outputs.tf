output "glue_log_group_name" {
  description = "Name of the CloudWatch log group for the Glue ETL job."
  value       = aws_cloudwatch_log_group.glue.name
}

output "glue_failure_alarm_arn" {
  description = "ARN of the CloudWatch alarm for Glue job failures."
  value       = aws_cloudwatch_metric_alarm.glue_job_failure.arn
}

output "alerts_sns_topic_arn" {
  description = "ARN of the SNS topic that receives all data-pipeline alerts."
  value       = aws_sns_topic.alerts.arn
}
