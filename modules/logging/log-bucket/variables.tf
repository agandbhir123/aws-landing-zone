variable "log_bucket_name" {
  description = "Name for the central CloudTrail log bucket. Must be globally unique across all of S3."
  type        = string
}

variable "organization_id" {
  description = "AWS Organizations ID (e.g. o-xxxxxxxxxx), used to scope the bucket policy to only this org"
  type        = string
}
