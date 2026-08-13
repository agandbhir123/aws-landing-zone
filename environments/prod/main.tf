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
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  assume_role {
    role_arn = "arn:aws:iam::${var.prod_account_id}:role/OrganizationAccountAccessRole"
  }

  default_tags {
    tags = {
      Project   = "aws-landing-zone"
      ManagedBy = "terraform"
      Env       = "prod"
    }
  }
}

module "cross_account_iam" {
  source = "../../modules/cross-account-iam"

  management_account_id = var.management_account_id
  account_purpose        = "prod"
  external_id            = var.external_id
}
