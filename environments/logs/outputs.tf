output "cross_account_role_arn" {
  value = module.cross_account_iam.role_arn
}

output "log_bucket_name" {
  value = module.log_bucket.bucket_name
}

output "log_bucket_arn" {
  value = module.log_bucket.bucket_arn
}

output "athena_workgroup" {
  value = module.log_bucket.athena_workgroup
}

output "glue_database" {
  value = module.log_bucket.glue_database
}
