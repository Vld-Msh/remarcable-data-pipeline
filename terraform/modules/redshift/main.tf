# modules/redshift/main.tf
# Redshift Serverless namespace + workgroup for the curated layer.

resource "aws_redshiftserverless_namespace" "main" {
  namespace_name      = "${var.name_prefix}-ns"
  admin_username      = var.admin_username
  admin_user_password = var.admin_password
  db_name             = "remarcable"

  # Associate the IAM role so the workgroup can read from S3 / Glue Catalog
  iam_roles = [var.redshift_role_arn]

  log_exports = ["useractivitylog", "userlog", "connectionlog"]
}

resource "aws_redshiftserverless_workgroup" "main" {
  namespace_name = aws_redshiftserverless_namespace.main.namespace_name
  workgroup_name = "${var.name_prefix}-wg"

  base_capacity       = var.base_capacity
  publicly_accessible = false

  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids

  # Enforce encrypted connections only
  config_parameter {
    parameter_key   = "require_ssl"
    parameter_value = "true"
  }

  config_parameter {
    parameter_key   = "enable_user_activity_logging"
    parameter_value = "true"
  }
}

# Resource policy restricts COPY/UNLOAD access to the curated bucket only
resource "aws_redshiftserverless_resource_policy" "curated_s3" {
  resource_arn = aws_redshiftserverless_namespace.main.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowRedshiftS3Access"
        Effect    = "Allow"
        Principal = { Service = "redshift.amazonaws.com" }
        Action    = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          var.curated_bucket_arn,
          "${var.curated_bucket_arn}/*"
        ]
      }
    ]
  })
}
