#!/usr/bin/env bash
# Prints current SG-rules quota value for each region (tab-separated).
# Usage: quick_check.sh [region …] — defaults to common four.

set -euo pipefail

SERVICE_CODE="vpc"
QUOTA_CODE="L-0EA8095F"
REGIONS=("us-east-1" "eu-west-2" "ap-southeast-1" "us-west-2")
[[ $# -gt 0 ]] && REGIONS=("$@")

printf "Region\tQuotaValue\n"
for r in "${REGIONS[@]}"; do
  value=$(aws service-quotas get-service-quota \
            --service-code "$SERVICE_CODE" \
            --quota-code   "$QUOTA_CODE" \
            --region "$r" \
            --query 'Quota.Value' --output text 2>/dev/null || echo "N/A")
  printf "%s\t%s\n" "$r" "$value"
done
