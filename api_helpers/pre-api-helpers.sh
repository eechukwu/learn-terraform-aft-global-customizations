#!/bin/bash
echo "Executing Pre-API Helpers"

# Basic checks...
if ! command -v aws >/dev/null 2>&1; then
    echo "ERROR: AWS CLI not found"
    exit 1
fi

if aws sts get-caller-identity >/dev/null 2>&1; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo "AWS credentials valid for account: $ACCOUNT_ID"
else
    echo "ERROR: AWS credentials invalid"
    exit 1
fi

# Clean up existing resources from failed deployments
echo "Cleaning up existing resources..."

# Delete existing IAM policies
POLICIES=(
    "aft-quota-manager-${ACCOUNT_ID}-logs"
    "aft-quota-manager-${ACCOUNT_ID}-dl" 
    "aft-quota-manager-${ACCOUNT_ID}"
)

for policy in "${POLICIES[@]}"; do
    if aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${policy}" >/dev/null 2>&1; then
        echo "Deleting policy: $policy"
        aws iam delete-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${policy}" || echo "Could not delete $policy"
    fi
done

# Delete existing Lambda function
LAMBDA_NAME="aft-quota-manager-${ACCOUNT_ID}"
if aws lambda get-function --function-name "$LAMBDA_NAME" >/dev/null 2>&1; then
    echo "Deleting Lambda function: $LAMBDA_NAME"
    aws lambda delete-function --function-name "$LAMBDA_NAME" || echo "Could not delete Lambda"
fi

# Delete existing IAM role
ROLE_NAME="aft-quota-manager-${ACCOUNT_ID}"
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
    echo "Deleting IAM role: $ROLE_NAME"
    # Detach policies first
    aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[].PolicyArn' --output text | xargs -r -n1 aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn
    aws iam delete-role --role-name "$ROLE_NAME" || echo "Could not delete role"
fi

# Delete existing log groups
LOG_GROUPS=(
    "/aws/lambda/aft-quota-manager-${ACCOUNT_ID}"
    "/aws/lambda/notify_slack"
)

for log_group in "${LOG_GROUPS[@]}"; do
    if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$log_group"; then
        echo "Deleting log group: $log_group"
        aws logs delete-log-group --log-group-name "$log_group" || echo "Could not delete log group"
    fi
done

echo "Cleanup completed - ready for fresh deployment"
echo "Pre-API helpers completed successfully"