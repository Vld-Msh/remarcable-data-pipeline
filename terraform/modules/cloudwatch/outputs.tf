output "glue_log_group_name"          { value = aws_cloudwatch_log_group.glue.name }
output "glue_failure_alarm_arn"       { value = aws_cloudwatch_metric_alarm.glue_job_failure.arn }
output "alerts_sns_topic_arn"         { value = aws_sns_topic.alerts.arn }
output "chatbot_configuration_arn"    { value = awscc_chatbot_slack_channel_configuration.alerts.arn }
