variable "workloads_ou_id" {
  description = "OU ID for the Workloads OU (parent of Dev/Prod)"
  type        = string
}

variable "security_ou_id" {
  description = "OU ID for the Security OU"
  type        = string
}

variable "logs_ou_id" {
  description = "OU ID for the Logs OU"
  type        = string
}

variable "approved_regions" {
  description = "List of AWS regions where activity is allowed in workload accounts"
  type        = list(string)
  default     = ["us-east-1", "us-east-2"]
}
