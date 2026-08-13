output "organization_id" {
  value = module.organizations.organization_id
}

output "security_account_id" {
  value = module.organizations.security_account_id
}

output "log_archive_account_id" {
  value = module.organizations.log_archive_account_id
}

output "dev_account_id" {
  value = module.organizations.dev_account_id
}

output "prod_account_id" {
  value = module.organizations.prod_account_id
}

output "scp_deny_public_s3_id" {
  value = module.scps.deny_public_s3_policy_id
}

output "scp_deny_disable_security_services_id" {
  value = module.scps.deny_disable_security_services_policy_id
}

output "scp_deny_outside_approved_regions_id" {
  value = module.scps.deny_outside_approved_regions_policy_id
}

output "scp_deny_root_user_id" {
  value = module.scps.deny_root_user_policy_id
}

output "scp_require_encryption_id" {
  value = module.scps.require_encryption_policy_id
}

output "org_trail_arn" {
  value = module.org_trail.trail_arn
}

output "guardduty_admin_account_id" {
  value = module.guardduty_delegated_admin.admin_account_id
}
