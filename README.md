# AWS Multi-Account Landing Zone

A production-style AWS multi-account landing zone built with Terraform. Implements
account isolation, org-wide security guardrails (SCPs), centralized audit logging,
and cross-account IAM access — the same foundational pattern used by platform/infra
teams to secure AWS environments at scale.

**Status: fully deployed and validated.** Every resource described below is live
in a real AWS Organization, not just planned.

## Why this exists

Most student AWS projects stop at a single account with IAM users and a couple of
S3 buckets. That doesn't reflect how AWS is actually run in a real org: multiple
accounts, isolated blast radius, guardrails enforced at the organization level
(not hoped for at the individual account level), and centralized logging that
can't be tampered with by the accounts being watched.

This project builds that pattern from scratch and proves it works with an
automated test suite that attempts real guardrail violations and confirms they're
blocked — not just claims the policies exist.

## Architecture

```
Management Account
│   owns: Organization, OUs, SCPs, org-wide CloudTrail trail, GuardDuty delegation
│
├── Security OU
│   └── Security/Audit Account
│         - GuardDuty delegated admin (detector monitors all 5 accounts)
│         - Cross-account role: read-only
│
├── Logs OU
│   └── Log Archive Account
│         - S3 bucket receiving CloudTrail logs from every account in the org
│         - Athena + Glue Data Catalog for SQL-queryable audit logs
│         - Cross-account role: read-only
│
└── Workloads OU
    ├── Dev Account
    │     - Cross-account role: PowerUser, minus IAM/Organizations writes
    │     - All 5 SCP guardrails enforced
    └── Prod Account
          - Same access pattern as Dev
```

**Guardrails enforced via Service Control Policies (SCPs), attached at the OU level:**
- Deny creation of public S3 buckets
- Require encryption at rest for new S3 objects and EBS volumes
- Deny actions outside approved regions (`us-east-1`, `us-east-2`)
- Deny use of the root user for anything except break-glass
- Deny disabling of CloudTrail, GuardDuty, or Config

Attaching at the OU level (not per-account) means every current and future
account dropped into Workloads/Security/Logs inherits these automatically —
zero manual setup required for new accounts.

**Cross-account access:** IAM roles with scoped trust policies and an
`external_id` condition replace shared credentials. No IAM users with
long-lived keys anywhere in the workload/security/logs accounts.

**Centralized logging:** every account's CloudTrail events (including the
management account's own root-user activity) land in one S3 bucket in the
Log Archive account, queryable via Athena. The bucket policy only allows
writes from `cloudtrail.amazonaws.com` scoped to this org's ID — no human or
role in any other account can write to or delete from it.

## Proof it works: automated guardrail test suite

`tests/run_guardrail_tests.sh` assumes the Dev account's cross-account role
and deliberately attempts 7 actions the SCPs should block, then verifies AWS
actually denied each one.

**Actual output from a live run:**

```
=== Assuming role in Dev account ===
Assumed role successfully. Running tests as the Dev cross-account role.

--- Test 1: attempt to make bucket public via ACL ---
  PASS - DenyPublicS3 (public-read ACL) (correctly denied)

--- Test 2: attempt to upload an unencrypted S3 object ---
  PASS - RequireEncryptionAtRest (unencrypted PutObject) (correctly denied)

--- Test 3: confirm an ENCRYPTED upload is allowed ---
  PASS - Encrypted PutObject should succeed (correctly allowed)

--- Test 4: attempt to create an unencrypted EBS volume ---
  PASS - RequireEncryptionAtRest (unencrypted EBS volume) (correctly denied)

--- Test 5: attempt to create an S3 bucket in a disallowed region (eu-west-1) ---
  PASS - DenyOutsideApprovedRegions (eu-west-1) (correctly denied)

--- Test 6: attempt to stop CloudTrail logging ---
  PASS - DenyDisableSecurityServices (cloudtrail:StopLogging) (correctly denied)

--- Test 7: attempt to create an IAM user ---
  PASS - DenyIAMAndOrgChanges (iam:CreateUser) (correctly denied)

================================================
  GUARDRAIL TEST SUMMARY
================================================
  Passed: 7   Failed: 0
================================================
All guardrails enforced correctly.
```

Test 3 is a deliberate "should succeed" case — without it, an overly broad
policy (e.g. one that blocked *all* S3 writes instead of just unencrypted
ones) would still show all green. It catches false-positive guardrails, not
just false negatives.

## A real bug found and fixed along the way

The `DenyDisableSecurityServices` SCP originally denied `guardduty:UpdateDetector`
outright, on the assumption that action is only used to turn GuardDuty off. In
practice, `UpdateDetector` is the *same* API call used to enable individual
GuardDuty protections (S3 protection, malware scanning) — so the SCP was
blocking legitimate configuration, not just disablement.

**Fix:** narrowed the deny list to the actions that actually disable GuardDuty
(`DeleteDetector`, `DisassociateFromMasterAccount`, `DisassociateMembers`,
`StopMonitoringMembers`), while leaving `UpdateDetector` allowed. This is a
good example of the SCP-tuning tradeoff every real security team runs into:
guardrails need to be scoped precisely enough to block the harmful action
without blocking the legitimate one that happens to share an API call.

## Repo structure

```
aws-landing-zone/
├── modules/
│   ├── organizations/        # AWS Organizations, OUs, member accounts
│   ├── scps/                 # Service Control Policies
│   ├── cross-account-iam/    # Cross-account roles + trust policies
│   ├── logging/
│   │   ├── log-bucket/       # S3 bucket + Athena/Glue (Logs account)
│   │   └── org-trail/        # Org-wide CloudTrail trail (management account)
│   └── guardduty/
│       ├── delegated-admin/  # Designates Security account as admin (management)
│       └── detector/         # GuardDuty detector + org auto-enrollment (Security)
├── environments/
│   ├── management/           # Root account: Organizations, SCPs, trail, delegation
│   ├── security/              # Security/audit account resources
│   ├── logs/                  # Log archive account resources
│   ├── dev/                   # Dev workload account
│   └── prod/                  # Prod workload account
├── tests/                     # Automated guardrail-violation test suite
└── docs/                      # Runbooks
```

## CI/CD

Every pull request that touches a `.tf` file triggers a GitHub Actions
workflow (`.github/workflows/terraform.yml`) that:

1. Checks formatting with `terraform fmt -check`
2. Runs `terraform init` + `terraform validate`
3. Runs `terraform plan` against the management environment and posts the
   diff in the workflow log

**Authentication uses OIDC, not stored AWS access keys.** GitHub's OIDC
provider is registered in the management account (`modules/github-oidc`),
and a dedicated IAM role trusts only this exact repo (`agandbhir123/aws-landing-zone`)
via the `sub` claim in GitHub's signed token — no other repo, fork, or
workflow anywhere can assume it. The role has `ReadOnlyAccess` plus scoped
write access to only the Terraform state bucket and lock table.

**CI never runs `terraform apply`.** This is deliberate: this repo controls
a real AWS Organization, and giving a CI pipeline write access to that is a
larger blast radius than a personal project needs to accept. Applies stay a
manual, human-run step from a local machine after reviewing the plan.

**One-time setup to make CI work in a fork or new copy of this repo:**
1. Apply `environments/management` once locally (as done throughout this
   README) to create the OIDC provider and IAM role
2. Copy the `github_actions_role_arn` output value
3. In the GitHub repo settings → Secrets and variables → Actions, add:
   - `AWS_GITHUB_ACTIONS_ROLE_ARN` = that ARN
   - `TF_VAR_security_account_email`, `TF_VAR_log_archive_account_email`,
     `TF_VAR_dev_account_email`, `TF_VAR_prod_account_email`,
     `TF_VAR_log_bucket_name` = same values as your local `terraform.tfvars`

## Status

- [x] Organizations + 5-account OU structure
- [x] SCPs (5 guardrails, attached at OU level)
- [x] Cross-account IAM roles (all 4 member accounts)
- [x] Centralized CloudTrail logging + Athena
- [x] GuardDuty delegated admin + org-wide auto-enrollment
- [x] Automated guardrail test suite (7/7 passing)
- [x] CI/CD (GitHub Actions) — fmt/validate/plan on every PR via OIDC, no stored AWS keys

## Cost note

Multiple accounts each accrue their own CloudTrail/GuardDuty/Config costs.
Tear down non-active environments (`terraform destroy` in dev/prod) when not
actively testing to avoid runaway billing.
