#!/usr/bin/env bash
# Multi-Region SG-quota validator – works with the float values AWS returns
set -euo pipefail

TARGET=200
SERVICE="vpc"
QUOTA="L-0EA8095F"
REGIONS=(us-east-1 eu-west-2 ap-southeast-1 us-west-2)

GREEN='\e[32m'; RED='\e[31m'; NC='\e[0m'

print_head() { printf "\n%-15s | %-9s | %-5s\n" "Region" "Status" "Value"; }

validate() {
  local region=$1
  local v_float
  v_float=$(aws service-quotas get-service-quota \
              --service-code "$SERVICE" --quota-code "$QUOTA" \
              --region "$region" --query 'Quota.Value' --output text)

  # **NEW** – remove the decimal so bash can compare
  local v_int; v_int=$(printf '%.0f' "$v_float")

  if (( v_int >= TARGET )); then
    printf "%-15s | ${GREEN}%-9s${NC} | %5s\n" "$region" "APPROVED" "$v_int"
    return 0
  else
    printf "%-15s | ${RED}%-9s${NC} | %5s\n" "$region" "PENDING"  "$v_int"
    return 1
  fi
}

main() {
  print_head
  local pending=0
  for r in "${REGIONS[@]}"; do
    validate "$r" || pending=1
  done
  return $pending        # 0 ↔ all done, non-zero ↔ wait/retry
}

main