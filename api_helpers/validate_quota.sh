#!/usr/bin/env bash
# Validate that the SG-rule quota is ≥ TARGET in each region
set -euo pipefail

TARGET=200            # what we want
SERVICE="vpc"
QUOTA="L-0EA8095F"
REGIONS=(us-east-1 eu-west-2 ap-southeast-1 us-west-2)

# colours for readability in CodeBuild logs
OK="\e[32m"; NO="\e[31m"; NC="\e[0m"

header() { printf "\n%-15s | %-9s | %-6s\n" "Region" "Status" "Value"; }

check_region () {
  local region=$1

  # pull the *float* value (e.g. 60.0)
  local value_float
  value_float=$(aws service-quotas get-service-quota \
                  --service-code "$SERVICE" \
                  --quota-code   "$QUOTA"  \
                  --region "$region" \
                  --query 'Quota.Value' --output text 2>/dev/null)

  # convert to integer so bash can compare safely
  local value_int
  value_int=$(printf '%.0f' "$value_float")

  if (( value_int >= TARGET )); then
      printf "%-15s | ${OK}%-9s${NC} | %6s\n" "$region" "APPROVED" "$value_int"
      return 0
  else
      printf "%-15s | ${NO}%-9s${NC} | %6s\n" "$region" "PENDING"  "$value_int"
      return 1
  fi
}

main () {
  header
  local pending=0
  for r in "${REGIONS[@]}"; do
      if ! check_region "$r"; then
          pending=1
      fi
  done
  return $pending       # 0 = all good, 1 = at least one still pending
}

main