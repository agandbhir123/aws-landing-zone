output "cross_account_role_arn" {
  value = module.cross_account_iam.role_arn
}

output "guardduty_detector_id" {
  value = module.guardduty_detector.detector_id
}
