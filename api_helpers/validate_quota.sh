#!/usr/bin/env bash
# Validates that the Security-Group rules quota (L-0EA8095F) is TARGET or higher.
# Usage: validate_quota.sh [region …]   # defaults to four regions if none provided.

set -euo pipefail

SERVICE_CODE="vpc"
QUOTA_CODE="L-0EA8095F"
TARGET=200

# Default regions – override by passing arguments.
REGIONS=("us-east-1" "eu-west-2" "ap-southeast-1" "us-west-2")
[[ $# -gt 0 ]] && REGIONS=("$@")

check() {
  local region=$1
  local value
  if ! value=$(aws service-quotas get-service-quota \
        --service-code "$SERVICE_CODE" \
        --quota-code   "$QUOTA_CODE" \
        --region       "$region" \
        --query 'Quota.Value' --output text 2>/dev/null); then
    echo "WARN    $region  unable to read quota" >&2
    return 1                # keep going but mark as warning
  fi

  if (( value >= TARGET )); then
    echo "OK      $region  $value"
  else
    echo "PENDING $region  $value (< $TARGET)" >&2
    return 2
  fi
}

status=0
for r in "${REGIONS[@]}"; do
  check "$r" || status=$?
done

exit $status