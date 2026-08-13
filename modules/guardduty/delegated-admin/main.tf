terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Designates the Security account as the GuardDuty delegated administrator
# for the whole organization. This must run from the MANAGEMENT account -
# only the management account can designate a delegated admin.
#
# Why delegate to Security instead of managing GuardDuty from management:
# it keeps the management account's blast radius small (it does org/billing/
# identity stuff, not security operations) and mirrors how real orgs split
# responsibilities - the security team owns security tooling, full stop.
# ---------------------------------------------------------------------------
resource "aws_guardduty_organization_admin_account" "this" {
  admin_account_id = var.security_account_id
}
