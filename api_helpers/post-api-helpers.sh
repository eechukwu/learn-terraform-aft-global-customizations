#!/usr/bin/env bash
# Post-apply hook for AFT: run quota validator every 5 min until
# all regions reach the target, or the attempt limit is hit.
set -euo pipefail

###############################################
# Optional role assumption (if env vars set)  #
###############################################
if [[ -n "${AWS_ROLE_ARN:-}" ]]; then
  : "${AWS_SESSION_NAME:?AWS_SESSION_NAME must be set when AWS_ROLE_ARN is provided}"
  read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN < <(
    aws sts assume-role \
      --role-arn        "$AWS_ROLE_ARN" \
      --role-session-name "$AWS_SESSION_NAME" \
      --query           'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
      --output          text
  )
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
fi

###############################################
# Validation loop                             #
###############################################
SCRIPT_DIR="$(dirname "$0")"
VALIDATOR="$SCRIPT_DIR/validate-quota.sh"
INTERVAL="${WAIT_SECONDS:-300}"   # 5 min default
MAX_ATTEMPTS="${MAX_ATTEMPTS:-24}" # 24 × 5 min = 2 h default

for ((attempt=1; attempt<=MAX_ATTEMPTS; attempt++)); do
  echo "[INFO] Attempt $attempt/$MAX_ATTEMPTS — running quota validator…"
  if "$VALIDATOR" "$@"; then
    echo "[INFO] Quota approved in all regions; exiting 0."
    exit 0
  fi
  echo "[INFO] Quota still pending; sleeping ${INTERVAL}s before retry."
  sleep "$INTERVAL"
done

echo "[ERROR] Quota still not approved after $((INTERVAL * MAX_ATTEMPTS / 60)) minutes."
exit 2