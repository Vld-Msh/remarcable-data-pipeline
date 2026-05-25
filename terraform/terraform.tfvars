# terraform.tfvars
# Non-sensitive runtime values. Sensitive values (passwords, secrets) should
# be supplied via environment variables (TF_VAR_*) or AWS Secrets Manager —
# never commit secrets to version control.

aws_region  = "us-east-1"
environment = "dev"
project     = "remarcable"
owner       = "data-engineering"

# S3
s3_force_destroy = true # safe to destroy in dev; set false in prod

# Glue
glue_job_worker_type  = "G.1X"
glue_job_num_workers  = 2
glue_crawler_schedule = "cron(0 6 * * ? *)"

# Redshift Serverless
redshift_base_capacity  = 8
redshift_admin_username = "admin"
# redshift_admin_password — set via TF_VAR_redshift_admin_password env var

# Networking — replace with actual VPC resource IDs before applying
redshift_vpc_subnet_ids         = ["subnet-xxxxxxxx", "subnet-yyyyyyyy"]
redshift_vpc_security_group_ids = ["sg-xxxxxxxx"]

# Alerting — email
alarm_email        = "data-alerts@remarcable.com"
log_retention_days = 90
