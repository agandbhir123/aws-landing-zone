terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ---------------------------------------------------------------------------
# The organization-wide CloudTrail trail. Must be created in the management
# account with is_organization_trail = true - this is what makes it apply
# to every current AND future member account automatically, and what
# prevents member accounts from disabling their own copy of it (they can't;
# it isn't theirs to disable, which is the whole point).
# ---------------------------------------------------------------------------
resource "aws_cloudtrail" "org_trail" {
  name                          = "org-trail"
  s3_bucket_name                = var.log_bucket_name
  is_organization_trail         = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  include_global_service_events = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = {
    Purpose = "org-wide-audit-log"
  }
}
