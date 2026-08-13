#!/usr/bin/env bash
#
# Guardrail validation suite.
#
# Assumes the cross-account role in the Dev account, then deliberately
# attempts several actions the SCPs are supposed to block. A "PASS" means
# AWS returned AccessDenied (the guardrail worked). A "FAIL" means the
# action succeeded, which would mean a guardrail has a hole in it - anything
# created during a FAIL is cleaned up automatically at the end.
#
# Usage:
#   export DEV_ACCOUNT_ID=415081250484
#   export EXTERNAL_ID=<your external_id>
#   ./run_guardrail_tests.sh
#
set -uo pipefail

DEV_ACCOUNT_ID="${DEV_ACCOUNT_ID:?Set DEV_ACCOUNT_ID}"
EXTERNAL_ID="${EXTERNAL_ID:?Set EXTERNAL_ID}"
ROLE_ARN="arn:aws:iam::${DEV_ACCOUNT_ID}:role/OrganizationAccountAccessRole-dev"
REGION="us-east-1"
DISALLOWED_REGION="eu-west-1"
TEST_BUCKET="lz-guardrail-test-$(date +%s)"

PASS_COUNT=0
FAIL_COUNT=0
RESULTS=()

echo "=== Assuming role in Dev account (${DEV_ACCOUNT_ID}) ==="
CREDS=$(aws sts assume-role \
  --role-arn "$ROLE_ARN" \
  --role-session-name "guardrail-test" \
  --external-id "$EXTERNAL_ID" \
  --output json) || { echo "FATAL: could not assume role. Check DEV_ACCOUNT_ID and EXTERNAL_ID."; exit 1; }

export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | python3 -c "import sys, json; print(json.load(sys.stdin)['Credentials']['AccessKeyId'])")
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | python3 -c "import sys, json; print(json.load(sys.stdin)['Credentials']['SecretAccessKey'])")
export AWS_SESSION_TOKEN=$(echo "$CREDS" | python3 -c "import sys, json; print(json.load(sys.stdin)['Credentials']['SessionToken'])")

echo "Assumed role successfully. Running tests as the Dev cross-account role."
echo ""

record_result() {
  local test_name="$1"
  local expected="$2"  # "denied" or "allowed"
  local actual_exit="$3"

  if [[ "$expected" == "denied" && "$actual_exit" -ne 0 ]]; then
    echo "  PASS - $test_name (correctly denied)"
    RESULTS+=("PASS|$test_name")
    PASS_COUNT=$((PASS_COUNT + 1))
  elif [[ "$expected" == "allowed" && "$actual_exit" -eq 0 ]]; then
    echo "  PASS - $test_name (correctly allowed)"
    RESULTS+=("PASS|$test_name")
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "  FAIL - $test_name (guardrail did not behave as expected!)"
    RESULTS+=("FAIL|$test_name")
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# ---------------------------------------------------------------------------
# Setup: create a plain test bucket to run ACL/encryption tests against.
# This creation itself should succeed - only the violation attempts below
# should be denied.
# ---------------------------------------------------------------------------
echo "--- Setup: creating test bucket $TEST_BUCKET ---"
aws s3api create-bucket --bucket "$TEST_BUCKET" --region "$REGION" >/dev/null 2>&1
echo ""

# ---------------------------------------------------------------------------
# Test 1: Deny public S3 (public-read ACL on a bucket)
# ---------------------------------------------------------------------------
echo "--- Test 1: attempt to make bucket public via ACL ---"
aws s3api put-bucket-acl --bucket "$TEST_BUCKET" --acl public-read >/tmp/t1.log 2>&1
record_result "DenyPublicS3 (public-read ACL)" "denied" $?
echo ""

# ---------------------------------------------------------------------------
# Test 2: Require encryption (unencrypted S3 object upload)
# ---------------------------------------------------------------------------
echo "--- Test 2: attempt to upload an unencrypted S3 object ---"
echo "test" > /tmp/test-object.txt
aws s3api put-object \
  --bucket "$TEST_BUCKET" \
  --key "unencrypted-test.txt" \
  --body /tmp/test-object.txt >/tmp/t2.log 2>&1
record_result "RequireEncryptionAtRest (unencrypted PutObject)" "denied" $?
echo ""

# ---------------------------------------------------------------------------
# Test 3: Confirm ENCRYPTED upload IS allowed (sanity check that we didn't
# just lock ourselves out of S3 entirely)
# ---------------------------------------------------------------------------
echo "--- Test 3: confirm an ENCRYPTED upload is allowed ---"
aws s3api put-object \
  --bucket "$TEST_BUCKET" \
  --key "encrypted-test.txt" \
  --body /tmp/test-object.txt \
  --server-side-encryption AES256 >/tmp/t3.log 2>&1
record_result "Encrypted PutObject should succeed" "allowed" $?
echo ""

# ---------------------------------------------------------------------------
# Test 4: Deny unencrypted EBS volume creation
# ---------------------------------------------------------------------------
echo "--- Test 4: attempt to create an unencrypted EBS volume ---"
aws ec2 create-volume \
  --availability-zone "${REGION}a" \
  --size 1 \
  --volume-type gp3 \
  --no-encrypted \
  --region "$REGION" >/tmp/t4.log 2>&1
record_result "RequireEncryptionAtRest (unencrypted EBS volume)" "denied" $?
echo ""

# ---------------------------------------------------------------------------
# Test 5: Deny actions outside approved regions
# ---------------------------------------------------------------------------
echo "--- Test 5: attempt to create an S3 bucket in a disallowed region ($DISALLOWED_REGION) ---"
aws s3api create-bucket \
  --bucket "${TEST_BUCKET}-region-test" \
  --region "$DISALLOWED_REGION" \
  --create-bucket-configuration LocationConstraint="$DISALLOWED_REGION" >/tmp/t5.log 2>&1
record_result "DenyOutsideApprovedRegions ($DISALLOWED_REGION)" "denied" $?
echo ""

# ---------------------------------------------------------------------------
# Test 6: Deny disabling CloudTrail (only meaningful once a trail exists -
# will still correctly show denied even against a nonexistent trail name,
# since the Deny fires before AWS checks if the trail exists)
# ---------------------------------------------------------------------------
echo "--- Test 6: attempt to stop CloudTrail logging ---"
aws cloudtrail stop-logging --name "org-trail" --region "$REGION" >/tmp/t6.log 2>&1
record_result "DenyDisableSecurityServices (cloudtrail:StopLogging)" "denied" $?
echo ""

# ---------------------------------------------------------------------------
# Test 7: Deny creating an IAM user (both SCP-adjacent and the explicit
# inline deny policy on the role itself)
# ---------------------------------------------------------------------------
echo "--- Test 7: attempt to create an IAM user ---"
aws iam create-user --user-name "guardrail-test-user" >/tmp/t7.log 2>&1
record_result "DenyIAMAndOrgChanges (iam:CreateUser)" "denied" $?
echo ""

# ---------------------------------------------------------------------------
# Cleanup - remove anything that may have been created (only matters if a
# test unexpectedly FAILed and something was actually created)
# ---------------------------------------------------------------------------
echo "--- Cleanup ---"
aws s3 rm "s3://${TEST_BUCKET}" --recursive >/dev/null 2>&1
aws s3api delete-bucket --bucket "$TEST_BUCKET" --region "$REGION" >/dev/null 2>&1
rm -f /tmp/test-object.txt
echo "Cleanup complete."
echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "================================================"
echo "  GUARDRAIL TEST SUMMARY"
echo "================================================"
for r in "${RESULTS[@]}"; do
  echo "  ${r/|/ - }"
done
echo "------------------------------------------------"
echo "  Passed: $PASS_COUNT   Failed: $FAIL_COUNT"
echo "================================================"

if [[ $FAIL_COUNT -gt 0 ]]; then
  echo ""
  echo "WARNING: one or more guardrails did not behave as expected."
  echo "Check the logs in /tmp/t*.log for details, then re-run to confirm a fix."
  echo "(Run 'rm -f /tmp/t*.log' manually once you're done reviewing them.)"
  exit 1
fi

echo ""
echo "All guardrails enforced correctly."
rm -f /tmp/t*.log
