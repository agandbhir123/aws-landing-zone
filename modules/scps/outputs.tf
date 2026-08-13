output "deny_public_s3_policy_id" {
  value = aws_organizations_policy.deny_public_s3.id
}

output "deny_disable_security_services_policy_id" {
  value = aws_organizations_policy.deny_disable_security_services.id
}

output "deny_outside_approved_regions_policy_id" {
  value = aws_organizations_policy.deny_outside_approved_regions.id
}

output "deny_root_user_policy_id" {
  value = aws_organizations_policy.deny_root_user.id
}

output "require_encryption_policy_id" {
  value = aws_organizations_policy.require_encryption.id
}
