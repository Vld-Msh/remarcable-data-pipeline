output "glue_role_arn" { value = aws_iam_role.glue.arn }
output "redshift_role_arn" { value = aws_iam_role.redshift.arn }
output "athena_role_arn" { value = aws_iam_role.athena.arn }
output "sagemaker_role_arn" { value = aws_iam_role.sagemaker.arn }
