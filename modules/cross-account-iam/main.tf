terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ---------------------------------------------------------------------------
# This module is applied PER ACCOUNT (dev, prod, security, logs) - it creates
# one cross-account role in whichever account's provider it's pointed at,
# trusting the management account to assume it.
#
# Why roles instead of IAM users with access keys:
#   - No long-lived credentials to leak
#   - Every assumption is logged in CloudTrail with a session identity
#   - Access can be revoked instantly by deleting/editing the role, no key
#     rotation needed
#   - This is literally how AWS expects multi-account access to work
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "cross_account_access" {
  name = "OrganizationAccountAccessRole-${var.account_purpose}"

  # Trust policy: ONLY the management account can assume this role, and only
  # if the caller also provides the correct external_id (belt-and-suspenders
  # against confused-deputy problems) and, in practice, has the right IAM
  # permissions in the management account to begin with.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowManagementAccountAssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.management_account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.external_id
          }
        }
      }
    ]
  })

  max_session_duration = 3600

  tags = {
    Purpose = "cross-account-access"
    Account = var.account_purpose
  }
}

# Permission level differs by account purpose:
#   - dev/prod (workloads): broad access for building things, but NOT admin -
#     no IAM user/role creation, no org changes, no leaving guardrails.
#   - security: read-only across the org (GuardDuty findings, Config, etc.)
#   - logs: read-only access to the CloudTrail/Athena logging setup.
resource "aws_iam_role_policy_attachment" "workload_access" {
  count = var.account_purpose == "dev" || var.account_purpose == "prod" ? 1 : 0

  role       = aws_iam_role.cross_account_access.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy_attachment" "readonly_access" {
  count = var.account_purpose == "security" || var.account_purpose == "logs" ? 1 : 0

  role       = aws_iam_role.cross_account_access.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Explicitly deny the workload roles from touching IAM or Organizations,
# even though PowerUserAccess normally excludes most IAM - this makes the
# restriction explicit and self-documenting rather than relying on
# PowerUserAccess's default exclusions alone.
resource "aws_iam_role_policy" "deny_iam_and_org_changes" {
  count = var.account_purpose == "dev" || var.account_purpose == "prod" ? 1 : 0

  name = "DenyIAMAndOrgChanges"
  role = aws_iam_role.cross_account_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyIAMWrites"
        Effect = "Deny"
        Action = [
          "iam:CreateUser",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:AttachRolePolicy",
          "iam:PutRolePolicy",
          "iam:CreateAccessKey"
        ]
        Resource = "*"
      },
      {
        Sid      = "DenyOrgChanges"
        Effect   = "Deny"
        Action   = "organizations:*"
        Resource = "*"
      }
    ]
  })
}
