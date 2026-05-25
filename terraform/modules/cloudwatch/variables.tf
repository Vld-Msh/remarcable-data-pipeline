variable "name_prefix" {
  description = "Resource name prefix (e.g. remarcable-dev)."
  type        = string
}

variable "glue_job_name" {
  description = "Name of the Glue ETL job to monitor."
  type        = string
}

variable "alarm_email" {
  description = "Email address subscribed to the SNS alerts topic."
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days."
  type        = number
  default     = 90
}
