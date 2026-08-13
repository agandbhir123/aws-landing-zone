output "role_arn" {
  description = "ARN of the cross-account role, to be assumed from the management account"
  value       = aws_iam_role.cross_account_access.arn
}

output "role_name" {
  value = aws_iam_role.cross_account_access.name
}
