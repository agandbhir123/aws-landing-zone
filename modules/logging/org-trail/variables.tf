variable "log_bucket_name" {
  description = "Name of the S3 bucket in the Logs account that will receive CloudTrail events (must already exist with the correct bucket policy)"
  type        = string
}
