output "namespace_arn" {
  value = aws_redshiftserverless_namespace.main.arn
}

output "workgroup_endpoint" {
  description = "JDBC endpoint for the Redshift Serverless workgroup."
  value       = aws_redshiftserverless_workgroup.main.endpoint[0].address
}
