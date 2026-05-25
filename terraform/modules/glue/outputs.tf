output "glue_database_name" { value = aws_glue_catalog_database.raw.name }
output "glue_crawler_name" { value = aws_glue_crawler.raw.name }
output "glue_job_name" { value = aws_glue_job.raw_to_staging.name }
