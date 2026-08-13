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

## Status

- [x] Organizations + 5-account OU structure
- [x] SCPs (5 guardrails, attached at OU level)
- [x] Cross-account IAM roles (all 4 member accounts)
- [x] Centralized CloudTrail logging + Athena
- [x] GuardDuty delegated admin + org-wide auto-enrollment
- [x] Automated guardrail test suite (7/7 passing)
- [ ] CI/CD (GitHub Actions) — optional stretch, not yet built

## Cost note

Multiple accounts each accrue their own CloudTrail/GuardDuty/Config costs.
Tear down non-active environments (`terraform destroy` in dev/prod) when not
actively testing to avoid runaway billing.
