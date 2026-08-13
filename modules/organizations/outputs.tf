output "organization_id" {
  value = aws_organizations_organization.this.id
}

output "organization_arn" {
  value = aws_organizations_organization.this.arn
}

output "root_id" {
  value = aws_organizations_organization.this.roots[0].id
}

output "security_ou_id" {
  value = aws_organizations_organizational_unit.security.id
}

output "logs_ou_id" {
  value = aws_organizations_organizational_unit.logs.id
}

output "workloads_ou_id" {
  value = aws_organizations_organizational_unit.workloads.id
}

output "workloads_dev_ou_id" {
  value = aws_organizations_organizational_unit.workloads_dev.id
}

output "workloads_prod_ou_id" {
  value = aws_organizations_organizational_unit.workloads_prod.id
}

output "security_account_id" {
  value = aws_organizations_account.security.id
}

output "log_archive_account_id" {
  value = aws_organizations_account.logs.id
}

output "dev_account_id" {
  value = aws_organizations_account.dev.id
}

output "prod_account_id" {
  value = aws_organizations_account.prod.id
}
