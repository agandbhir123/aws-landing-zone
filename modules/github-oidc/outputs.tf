output "role_arn" {
  description = "ARN to paste into the GitHub Actions workflow's role-to-assume input"
  value       = aws_iam_role.github_actions_ci.arn
}
