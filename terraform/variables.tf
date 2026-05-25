# variables.tf — all configurable values; set real values in terraform.tfvars

variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (dev | staging | prod)."
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "project" {
  description = "Project name used in resource naming and tags."
  type        = string
  default     = "remarcable"
}

variable "owner" {
  description = "Team or individual responsible for these resources (for tagging)."
  type        = string
  default     = "data-engineering"
}

# ---------------------------------------------------------------------------
# S3
# ---------------------------------------------------------------------------
variable "s3_force_destroy" {
  description = "Allow Terraform to destroy non-empty S3 buckets. Set false in prod."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Glue
# ---------------------------------------------------------------------------
variable "glue_job_worker_type" {
  description = "Glue worker type (G.1X | G.2X | G.025X)."
  type        = string
  default     = "G.1X"
}

variable "glue_job_num_workers" {
  description = "Number of Glue DPU workers."
  type        = number
  default     = 2
}

variable "glue_crawler_schedule" {
  description = "Cron schedule for the Glue crawler (UTC). Empty string = no schedule (manual trigger)."
  type        = string
  default     = "cron(0 6 * * ? *)"   # 06:00 UTC daily
}

# ---------------------------------------------------------------------------
# Redshift Serverless
# ---------------------------------------------------------------------------
variable "redshift_base_capacity" {
  description = "Redshift Serverless base RPU capacity (8–512, multiples of 8)."
  type        = number
  default     = 8
}

variable "redshift_admin_username" {
  description = "Admin username for the Redshift namespace."
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "redshift_admin_password" {
  description = "Admin password for the Redshift namespace. Must meet Redshift complexity requirements."
  type        = string
  sensitive   = true
}

variable "redshift_vpc_subnet_ids" {
  description = "List of subnet IDs for the Redshift Serverless workgroup."
  type        = list(string)
}

variable "redshift_vpc_security_group_ids" {
  description = "List of security group IDs for the Redshift Serverless workgroup."
  type        = list(string)
}

# ---------------------------------------------------------------------------
# CloudWatch / Alerting
# ---------------------------------------------------------------------------
variable "alarm_email" {
  description = "Email address to receive CloudWatch alarm notifications for Glue failures."
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days."
  type        = number
  default     = 90
}
