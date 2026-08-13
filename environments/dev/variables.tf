variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "dev_account_id" {
  description = "Account ID of the dev workload account (from `terraform output dev_account_id` in environments/management)"
  type        = string
}

variable "management_account_id" {
  description = "Account ID of the management account"
  type        = string
}

variable "external_id" {
  description = "Shared secret for the AssumeRole trust condition. Generate with `openssl rand -hex 16`. Must match across all environments and any tooling that assumes these roles."
  type        = string
  sensitive   = true
}
