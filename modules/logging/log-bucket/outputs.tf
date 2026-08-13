output "bucket_name" {
  value = aws_s3_bucket.cloudtrail_logs.id
}

output "bucket_arn" {
  value = aws_s3_bucket.cloudtrail_logs.arn
}

output "athena_workgroup" {
  value = aws_athena_workgroup.cloudtrail.name
}

output "glue_database" {
  value = aws_glue_catalog_database.cloudtrail.name
}

output "glue_table" {
  value = aws_glue_catalog_table.cloudtrail.name
}
