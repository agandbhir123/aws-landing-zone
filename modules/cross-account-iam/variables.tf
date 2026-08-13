variable "management_account_id" {
  description = "Account ID of the management account, allowed to assume this role"
  type        = string
}

variable "account_purpose" {
  description = "What this account is for: dev, prod, security, or logs. Controls permission level."
  type        = string

  validation {
    condition     = contains(["dev", "prod", "security", "logs"], var.account_purpose)
    error_message = "account_purpose must be one of: dev, prod, security, logs."
  }
}

variable "external_id" {
  description = "A shared secret required in the AssumeRole call, as a defense against confused-deputy attacks. Generate with `openssl rand -hex 16` and keep it out of version control."
  type        = string
  sensitive   = true
}
