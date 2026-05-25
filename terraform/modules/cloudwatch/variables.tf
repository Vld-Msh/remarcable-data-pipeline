variable "name_prefix"        { type = string }
variable "glue_job_name"      { type = string }
variable "alarm_email"        { type = string }
variable "log_retention_days" { type = number; default = 90 }
variable "slack_workspace_id" { type = string }
variable "slack_channel_id"   { type = string }
