terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ---------------------------------------------------------------------------
# The AWS Organization itself. This must be created (or already exist) in the
# management account. All feature set (not just consolidated billing) is
# required so SCPs can be attached.
# ---------------------------------------------------------------------------
resource "aws_organizations_organization" "this" {
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "guardduty.amazonaws.com",
    "sso.amazonaws.com",
    "config.amazonaws.com",
  ]

  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
  ]

  feature_set = "ALL"
}

# ---------------------------------------------------------------------------
# Organizational Units
# ---------------------------------------------------------------------------
resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "logs" {
  name      = "Logs"
  parent_id = aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "workloads_dev" {
  name      = "Dev"
  parent_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_organizational_unit" "workloads_prod" {
  name      = "Prod"
  parent_id = aws_organizations_organizational_unit.workloads.id
}

# ---------------------------------------------------------------------------
# Member accounts
#
# NOTE: aws_organizations_account creates a REAL AWS account. Each one is a
# separate billing/security boundary. Emails must be unique across all of AWS,
# not just your org (Gmail "+" aliases work well: you+lz-security@gmail.com).
# ---------------------------------------------------------------------------
resource "aws_organizations_account" "security" {
  name      = "security-audit"
  email     = var.security_account_email
  parent_id = aws_organizations_organizational_unit.security.id

  # Prevents Terraform from trying to close the account on destroy - member
  # account closure has to be deliberate, not a fat-fingered `terraform destroy`.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Purpose = "security-audit"
  }
}

resource "aws_organizations_account" "logs" {
  name      = "log-archive"
  email     = var.log_archive_account_email
  parent_id = aws_organizations_organizational_unit.logs.id

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Purpose = "log-archive"
  }
}

resource "aws_organizations_account" "dev" {
  name      = "workload-dev"
  email     = var.dev_account_email
  parent_id = aws_organizations_organizational_unit.workloads_dev.id

  tags = {
    Purpose = "workload-dev"
  }
}

resource "aws_organizations_account" "prod" {
  name      = "workload-prod"
  email     = var.prod_account_email
  parent_id = aws_organizations_organizational_unit.workloads_prod.id

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Purpose = "workload-prod"
  }
}
