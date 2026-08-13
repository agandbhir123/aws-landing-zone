variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "log_archive_account_id" {
  type = string
}

variable "management_account_id" {
  type = string
}

variable "external_id" {
  type      = string
  sensitive = true
}

variable "log_bucket_name" {
  description = "Globally-unique S3 bucket name for the central CloudTrail log bucket"
  type        = string
}

variable "organization_id" {
  description = "AWS Organizations ID (from `terraform output organization_id` in environments/management)"
  type        = string
}
