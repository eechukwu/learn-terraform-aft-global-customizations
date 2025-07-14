#!/bin/bash

echo "Executing Pre-API Helpers"

# Basic environment validation
if ! command -v aws >/dev/null 2>&1; then
    echo "ERROR: AWS CLI not found"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "WARNING: jq not found - JSON output will be limited"
fi

# Validate AWS credentials
if aws sts get-caller-identity >/dev/null 2>&1; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo "AWS credentials valid for account: $ACCOUNT_ID"
else
    echo "ERROR: AWS credentials invalid"
    exit 1
fi

# Validate required AWS permissions
echo "Validating AWS permissions..."

if ! aws lambda list-functions --max-items 1 >/dev/null 2>&1; then
    echo "ERROR: Lambda permissions missing"
    exit 1
fi

if ! aws service-quotas list-services --max-items 1 >/dev/null 2>&1; then
    echo "ERROR: Service Quotas permissions missing"
    exit 1
fi

echo "Prerequisites validated successfully"

# Check Slack configuration
SSM_PARAMETER_NAME="/aft/slack/quota-manager-bot-token"

if aws ssm get-parameter --name "$SSM_PARAMETER_NAME" --with-decryption >/dev/null 2>&1; then
    echo "SSM parameter $SSM_PARAMETER_NAME already exists"
    CURRENT_VALUE=$(aws ssm get-parameter --name "$SSM_PARAMETER_NAME" --with-decryption --query 'Parameter.Value' --output text)
    if [[ "$CURRENT_VALUE" == *"dummy-token"* ]]; then
        echo "Parameter contains dummy token - update required for Slack notifications"
    else
        echo "Real Slack token detected"
    fi
else
    echo "SSM parameter will be created by Terraform"
fi

echo "Quota management will be configured for regions defined in locals.tf"
echo "Pre-API helpers completed successfully"