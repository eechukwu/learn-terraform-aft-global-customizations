#!/bin/bash
echo "Executing Pre-API Helpers"

# Check prerequisites
if ! command -v aws >/dev/null 2>&1; then
    echo "ERROR: AWS CLI not found"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "WARNING: jq not found - JSON output will be limited"
fi

if aws sts get-caller-identity >/dev/null 2>&1; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo "AWS credentials valid for account: $ACCOUNT_ID"
else
    echo "ERROR: AWS credentials invalid"
    exit 1
fi

if ! aws lambda list-functions --max-items 1 >/dev/null 2>&1; then
    echo "ERROR: Lambda permissions missing"
    exit 1
fi

if ! aws service-quotas list-services --max-items 1 >/dev/null 2>&1; then
    echo "ERROR: Service Quotas permissions missing"
    exit 1
fi

echo "Prerequisites validated successfully"
echo "Quota management will be configured for regions defined in locals.tf"
echo "Pre-API helpers completed successfully"