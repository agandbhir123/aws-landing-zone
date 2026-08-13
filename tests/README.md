# Guardrail Validation Suite

This is the piece that turns "I wrote some SCPs" into "I proved my guardrails
work." It assumes the cross-account role in the Dev account and deliberately
attempts 7 actions that the SCPs should block, then verifies each one was
actually denied by AWS - not just assumed to be denied by reading the policy.

## What it tests

| # | Action attempted | Guardrail being tested | Expected result |
|---|---|---|---|
| 1 | Set a bucket ACL to `public-read` | DenyPublicS3 | Denied |
| 2 | Upload an S3 object with no encryption | RequireEncryptionAtRest | Denied |
| 3 | Upload an S3 object WITH encryption | (sanity check) | **Allowed** |
| 4 | Create an unencrypted EBS volume | RequireEncryptionAtRest | Denied |
| 5 | Create an S3 bucket in `eu-west-1` | DenyOutsideApprovedRegions | Denied |
| 6 | Stop CloudTrail logging | DenyDisableSecurityServices | Denied |
| 7 | Create a new IAM user | DenyIAMAndOrgChanges | Denied |

Test 3 is intentionally a "should succeed" case. Without it, a suite that's
too aggressive (e.g. accidentally blocking ALL S3 writes instead of just
unencrypted ones) would still show all green - test 3 catches that failure
mode.

## Running it

```bash
export DEV_ACCOUNT_ID=415081250484
export EXTERNAL_ID=<your external_id from openssl rand -hex 16>
chmod +x run_guardrail_tests.sh
./run_guardrail_tests.sh
```

Requires: AWS CLI configured with your management-account credentials
(the ones with permission to assume `OrganizationAccountAccessRole-dev`),
and `python3` available on PATH (used to parse the assume-role JSON output).

## Reading the output

Each test prints `PASS` or `FAIL` with a short reason. A `FAIL` means AWS
allowed something it should have blocked - that's a real gap in your
guardrails, not a script bug, and is worth investigating immediately. The
script cleans up anything it creates (the test bucket, any objects) whether
tests pass or fail, so re-running it is always safe.

## Why this matters for the "is this resume-worthy" conversation

Anyone can write an SCP and claim it works. Very few people actually prove
it by attempting the violation and capturing AWS's denial. This script - and
its output - is the artifact that makes the difference in an interview:
"I wrote guardrails" vs. "I wrote guardrails and have a test suite proving
all 7 fire correctly."
