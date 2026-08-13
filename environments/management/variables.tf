variable "aws_region" {
  description = "Primary AWS region for management account resources"
  type        = string
  default     = "us-east-1"
}

variable "security_account_email" {
  type = string
}

variable "log_archive_account_email" {
  type = string
}

variable "dev_account_email" {
  type = string
}

variable "prod_account_email" {
  type = string
}

variable "log_bucket_name" {
  description = "Name of the S3 bucket in the Logs account (must match what was created in environments/logs)"
  type        = string
}
