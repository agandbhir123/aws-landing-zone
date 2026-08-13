variable "github_repo" {
  description = "GitHub repo allowed to assume this role, in owner/repo format (e.g. agandbhir123/aws-landing-zone)"
  type        = string
}

variable "tfstate_bucket_name" {
  description = "Name of the S3 bucket storing Terraform state"
  type        = string
}

variable "tflock_table_name" {
  description = "Name of the DynamoDB table used for Terraform state locking"
  type        = string
  default     = "terraform-locks"
}

variable "aws_region" {
  description = "AWS region the state lock table lives in"
  type        = string
  default     = "us-east-1"
}
