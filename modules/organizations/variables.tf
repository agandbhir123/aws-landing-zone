variable "security_account_email" {
  description = "Unique email for the security/audit account (use a + alias, e.g. you+lz-security@gmail.com)"
  type        = string
}

variable "log_archive_account_email" {
  description = "Unique email for the log archive account"
  type        = string
}

variable "dev_account_email" {
  description = "Unique email for the dev workload account"
  type        = string
}

variable "prod_account_email" {
  description = "Unique email for the prod workload account"
  type        = string
}
