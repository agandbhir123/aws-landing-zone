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
    key            = "management/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "aws-landing-zone"
      ManagedBy = "terraform"
      Env       = "management"
    }
  }
}

module "organizations" {
  source = "../../modules/organizations"

  security_account_email    = var.security_account_email
  log_archive_account_email = var.log_archive_account_email
  dev_account_email         = var.dev_account_email
  prod_account_email        = var.prod_account_email
}

module "scps" {
  source = "../../modules/scps"

  workloads_ou_id  = module.organizations.workloads_ou_id
  security_ou_id   = module.organizations.security_ou_id
  logs_ou_id       = module.organizations.logs_ou_id
  approved_regions = ["us-east-1", "us-east-2"]
}

# NOTE: apply the `logs` environment FIRST - this module points at a bucket
# (and bucket policy) that must already exist in the Logs account before
# CloudTrail will accept it as a destination.
module "org_trail" {
  source = "../../modules/logging/org-trail"

  log_bucket_name = var.log_bucket_name
}

# NOTE: apply this AFTER the organizations module (security account must
# exist) but the actual detector (in environments/security) can be applied
# any time after this succeeds.
module "guardduty_delegated_admin" {
  source = "../../modules/guardduty/delegated-admin"

  security_account_id = module.organizations.security_account_id
}
