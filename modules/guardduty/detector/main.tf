terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ---------------------------------------------------------------------------
# The actual GuardDuty detector. Must be created in the Security account
# AFTER that account has been designated as the delegated admin (see the
# delegated-admin module, applied from the management account first).
# ---------------------------------------------------------------------------
resource "aws_guardduty_detector" "this" {
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = false # no EKS in this project - avoids paying for unused coverage
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = {
    Purpose = "org-guardduty-delegated-admin"
  }
}

# ---------------------------------------------------------------------------
# Auto-enrolls every CURRENT and FUTURE member account into GuardDuty
# automatically. This is the payoff of the delegated-admin pattern: a new
# account dropped into the org later gets threat detection with zero manual
# setup, the same way it automatically inherits the SCPs.
# ---------------------------------------------------------------------------
resource "aws_guardduty_organization_configuration" "this" {
  detector_id                      = aws_guardduty_detector.this.id
  auto_enable_organization_members = "ALL"
}
