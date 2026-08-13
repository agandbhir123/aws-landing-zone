terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "aaravgandbhir-landing-zone-tfstate"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

# ---------------------------------------------------------------------------
# This provider authenticates using YOUR management-account credentials
# (same `aws` CLI profile you've been using), then immediately assumes the
# built-in "OrganizationAccountAccessRole" that AWS auto-creates in every
# member account at account-creation time. That role already trusts the
# management account with full admin - no external_id needed for this one,
# since AWS creates the trust policy itself.
#
# We use this ONE TIME, essentially, to deploy the more restricted, custom
# cross-account role (with external_id + scoped permissions) that your
# actual day-to-day tooling should use going forward.
# ---------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region

  assume_role {
    role_arn = "arn:aws:iam::${var.dev_account_id}:role/OrganizationAccountAccessRole"
  }

  default_tags {
    tags = {
      Project   = "aws-landing-zone"
      ManagedBy = "terraform"
      Env       = "dev"
    }
  }
}

module "cross_account_iam" {
  source = "../../modules/cross-account-iam"

  management_account_id = var.management_account_id
  account_purpose        = "dev"
  external_id            = var.external_id
}
