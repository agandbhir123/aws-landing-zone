terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ---------------------------------------------------------------------------
# SCP 1: Deny public S3 buckets
#
# Blocks the specific S3 actions that would make a bucket or object public.
# This does NOT block S3 usage entirely - only the actions that flip
# something to public.
# ---------------------------------------------------------------------------
resource "aws_organizations_policy" "deny_public_s3" {
  name        = "DenyPublicS3"
  description = "Deny actions that make S3 buckets or objects publicly accessible"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyPublicACLs"
        Effect = "Deny"
        Action = [
          "s3:PutBucketAcl",
          "s3:PutObjectAcl",
          "s3:PutBucketPublicAccessBlock"
        ]
        Resource = "*"
        Condition = {
          StringEqualsIfExists = {
            "s3:x-amz-acl" = ["public-read", "public-read-write"]
          }
        }
      },
      {
        Sid    = "DenyDisablingPublicAccessBlock"
        Effect = "Deny"
        Action = [
          "s3:PutAccountPublicAccessBlock"
        ]
        Resource = "*"
        Condition = {
          "Bool" = {
            "s3:PublicAccessBlockConfiguration:BlockPublicAcls"       = "false"
            "s3:PublicAccessBlockConfiguration:BlockPublicPolicy"     = "false"
            "s3:PublicAccessBlockConfiguration:IgnorePublicAcls"      = "false"
            "s3:PublicAccessBlockConfiguration:RestrictPublicBuckets" = "false"
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# SCP 2: Deny disabling security services
#
# Prevents anyone (even account admins) from turning off CloudTrail,
# GuardDuty, or Config in member accounts. This is what makes "centralized,
# tamper-resistant logging" actually true instead of aspirational.
# ---------------------------------------------------------------------------
resource "aws_organizations_policy" "deny_disable_security_services" {
  name        = "DenyDisableSecurityServices"
  description = "Deny disabling CloudTrail, GuardDuty, or Config"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyCloudTrailTampering"
        Effect = "Deny"
        Action = [
          "cloudtrail:StopLogging",
          "cloudtrail:DeleteTrail",
          "cloudtrail:UpdateTrail"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyGuardDutyTampering"
        Effect = "Deny"
        Action = [
          "guardduty:DeleteDetector",
          "guardduty:DisassociateFromMasterAccount",
          "guardduty:DisassociateMembers",
          "guardduty:StopMonitoringMembers"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyConfigTampering"
        Effect = "Deny"
        Action = [
          "config:DeleteConfigRule",
          "config:DeleteConfigurationRecorder",
          "config:DeleteDeliveryChannel",
          "config:StopConfigurationRecorder"
        ]
        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# SCP 3: Deny actions outside approved regions
#
# Restricts almost all activity to approved regions. A short allowlist of
# global/always-needed services is exempted (IAM, Organizations, Support,
# CloudFront, Route53, STS, Billing) since those are global-scope by design.
# ---------------------------------------------------------------------------
resource "aws_organizations_policy" "deny_outside_approved_regions" {
  name        = "DenyOutsideApprovedRegions"
  description = "Deny actions taken outside the approved region list"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyOutsideApprovedRegions"
        Effect = "Deny"
        NotAction = [
          "iam:*",
          "organizations:*",
          "route53:*",
          "route53domains:*",
          "cloudfront:*",
          "support:*",
          "sts:*",
          "budgets:*",
          "ce:*",
          "health:*",
          "trustedadvisor:*",
          "waf:*",
          "wafv2:*",
          "shield:*"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = var.approved_regions
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# SCP 4: Deny root user actions
#
# Root should only ever be used for documented break-glass scenarios (e.g.
# closing an account). This blocks essentially all root API activity.
# ---------------------------------------------------------------------------
resource "aws_organizations_policy" "deny_root_user" {
  name        = "DenyRootUser"
  description = "Deny nearly all actions when called by the account root user"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyRootUserActions"
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:PrincipalArn" = "arn:aws:iam::*:root"
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# SCP 5: Require encryption at rest (S3 + EBS)
#
# Denies creating unencrypted S3 objects or EBS volumes.
# ---------------------------------------------------------------------------
resource "aws_organizations_policy" "require_encryption" {
  name        = "RequireEncryptionAtRest"
  description = "Deny creation of unencrypted S3 objects or EBS volumes"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyUnencryptedS3Uploads"
        Effect   = "Deny"
        Action   = "s3:PutObject"
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = ["AES256", "aws:kms"]
          }
        }
      },
      {
        Sid      = "DenyUnencryptedEBSVolumes"
        Effect   = "Deny"
        Action   = "ec2:CreateVolume"
        Resource = "*"
        Condition = {
          "Bool" = {
            "ec2:Encrypted" = "false"
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Policy attachments
#
# Attached at the OU level (not per-account) - this is the whole point of
# using Organizations instead of per-account IAM policies. Every current
# and future account dropped into these OUs automatically inherits these
# guardrails with zero extra work.
# ---------------------------------------------------------------------------
resource "aws_organizations_policy_attachment" "workloads_deny_public_s3" {
  policy_id = aws_organizations_policy.deny_public_s3.id
  target_id = var.workloads_ou_id
}

resource "aws_organizations_policy_attachment" "workloads_deny_disable_security" {
  policy_id = aws_organizations_policy.deny_disable_security_services.id
  target_id = var.workloads_ou_id
}

resource "aws_organizations_policy_attachment" "workloads_deny_region" {
  policy_id = aws_organizations_policy.deny_outside_approved_regions.id
  target_id = var.workloads_ou_id
}

resource "aws_organizations_policy_attachment" "workloads_deny_root" {
  policy_id = aws_organizations_policy.deny_root_user.id
  target_id = var.workloads_ou_id
}

resource "aws_organizations_policy_attachment" "workloads_require_encryption" {
  policy_id = aws_organizations_policy.require_encryption.id
  target_id = var.workloads_ou_id
}

# Security and Logs OUs get the tamper-protection + root-deny policies too,
# but NOT the region restriction (GuardDuty/Config sometimes need multi-region
# visibility) and not the public-S3 block in as strict a form, since the log
# archive bucket policy handles that more precisely at the resource level.
resource "aws_organizations_policy_attachment" "security_deny_disable_security" {
  policy_id = aws_organizations_policy.deny_disable_security_services.id
  target_id = var.security_ou_id
}

resource "aws_organizations_policy_attachment" "security_deny_root" {
  policy_id = aws_organizations_policy.deny_root_user.id
  target_id = var.security_ou_id
}

resource "aws_organizations_policy_attachment" "logs_deny_disable_security" {
  policy_id = aws_organizations_policy.deny_disable_security_services.id
  target_id = var.logs_ou_id
}

resource "aws_organizations_policy_attachment" "logs_deny_root" {
  policy_id = aws_organizations_policy.deny_root_user.id
  target_id = var.logs_ou_id
}
