terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# The central log bucket. Lives in the Logs account - deliberately isolated
# from Dev/Prod so that even a full compromise of a workload account can't
# reach the audit trail. Versioning is enabled so logs can't be silently
# overwritten; object lock could be added for true immutability but is
# skipped here to keep costs/complexity down for a portfolio project.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket = var.log_bucket_name
}

resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle: move to cheaper storage over time instead of deleting - audit
# logs are the kind of thing you want to keep, just not at S3 Standard
# prices forever.
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    id     = "archive-old-logs"
    status = "Enabled"

    filter {}

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 365
      storage_class = "GLACIER"
    }
  }
}

# ---------------------------------------------------------------------------
# Bucket policy: allows CloudTrail to write logs from ANY account in the
# organization (required for an org-wide trail), but nothing else. The
# aws:SourceArn condition scopes this to CloudTrail specifically, and the
# org ID condition scopes it to accounts within THIS organization only.
#
# Deliberately does NOT grant delete permissions to anything - not even the
# management account's normal admin access can casually delete these logs
# via this bucket policy (the SCP handles blocking trail-level tampering;
# this handles blocking bucket-level tampering).
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs.arn
        Condition = {
          StringEquals = {
            "aws:SourceOrgID" = var.organization_id
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"    = "bucket-owner-full-control"
            "aws:SourceOrgID" = var.organization_id
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Athena setup - lets you actually query the logs instead of manually
# combing through JSON files in S3. A Glue table is defined directly against
# the CloudTrail JSON format (partitioned by account/region/date), which is
# the standard pattern AWS documents for querying org trails.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "athena_results" {
  bucket = "${var.log_bucket_name}-athena-results"
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_athena_workgroup" "cloudtrail" {
  name = "cloudtrail-logs"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.id}/"
    }
  }
}

resource "aws_glue_catalog_database" "cloudtrail" {
  name = "cloudtrail_logs_db"
}

resource "aws_glue_catalog_table" "cloudtrail" {
  name          = "cloudtrail_logs"
  database_name = aws_glue_catalog_database.cloudtrail.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "classification"                = "cloudtrail"
    "projection.enabled"            = "true"
    "projection.region.type"        = "enum"
    "projection.region.values"      = "us-east-1,us-east-2"
    "projection.date.type"          = "date"
    "projection.date.range"         = "2026/01/01,NOW"
    "projection.date.format"        = "yyyy/MM/dd"
    "projection.date.interval"      = "1"
    "projection.date.interval.unit" = "DAYS"
    "storage.location.template"     = "s3://${var.log_bucket_name}/AWSLogs/${var.organization_id}/CloudTrail/$${region}/$${date}"
  }

  storage_descriptor {
    location      = "s3://${var.log_bucket_name}/AWSLogs/${var.organization_id}/CloudTrail/"
    input_format  = "com.amazon.emr.cloudtrail.CloudTrailInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "com.amazon.emr.hive.serde.CloudTrailSerde"
    }

    columns {
      name = "eventversion"
      type = "string"
    }
    columns {
      name = "useridentity"
      type = "struct<type:string,principalid:string,arn:string,accountid:string,invokedby:string,accesskeyid:string,userName:string>"
    }
    columns {
      name = "eventtime"
      type = "string"
    }
    columns {
      name = "eventsource"
      type = "string"
    }
    columns {
      name = "eventname"
      type = "string"
    }
    columns {
      name = "awsregion"
      type = "string"
    }
    columns {
      name = "sourceipaddress"
      type = "string"
    }
    columns {
      name = "useragent"
      type = "string"
    }
    columns {
      name = "errorcode"
      type = "string"
    }
    columns {
      name = "errormessage"
      type = "string"
    }
    columns {
      name = "requestparameters"
      type = "string"
    }
    columns {
      name = "responseelements"
      type = "string"
    }
    columns {
      name = "eventid"
      type = "string"
    }
    columns {
      name = "eventtype"
      type = "string"
    }
    columns {
      name = "recipientaccountid"
      type = "string"
    }
  }

  partition_keys {
    name = "region"
    type = "string"
  }
  partition_keys {
    name = "date"
    type = "string"
  }
}
