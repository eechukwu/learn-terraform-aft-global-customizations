#!/bin/bash

echo "Executing Pre-API Helpers"

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

echo "Cleaning up existing resources..."

LAMBDA_FUNCTIONS=(
    "aft-quota-manager-${ACCOUNT_ID}"
    "notify_slack"
)
for fn in "${LAMBDA_FUNCTIONS[@]}"; do
    if aws lambda get-function --function-name "$fn" >/dev/null 2>&1; then
        echo "Deleting Lambda function: $fn"
        aws lambda delete-function --function-name "$fn" || echo "Could not delete Lambda $fn"
    else
        echo "Lambda function $fn does not exist - skipping"
    fi
done

ROLES=(
    "aft-quota-manager-${ACCOUNT_ID}"
    "lambda-notify_slack"
)
for role in "${ROLES[@]}"; do
    if aws iam get-role --role-name "$role" >/dev/null 2>&1; then
        echo "Deleting IAM role: $role"
        aws iam list-attached-role-policies --role-name "$role" \
            --query 'AttachedPolicies[].PolicyArn' --output text \
            | xargs -r -n1 aws iam detach-role-policy --role-name "$role" --policy-arn
        aws iam delete-role --role-name "$role" || echo "Could not delete role $role"
    else
        echo "IAM role $role does not exist - skipping"
    fi
done

POLICIES=(
    "aft-quota-manager-${ACCOUNT_ID}-logs"
    "aft-quota-manager-${ACCOUNT_ID}-dl"
    "aft-quota-manager-${ACCOUNT_ID}"
    "lambda-notify_slack"
)
for policy in "${POLICIES[@]}"; do
    ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${policy}"
    if aws iam get-policy --policy-arn "$ARN" >/dev/null 2>&1; then
        echo "Deleting IAM policy: $policy"
        aws iam delete-policy --policy-arn "$ARN" || echo "Could not delete policy $policy"
    else
        echo "IAM policy $policy does not exist - skipping"
    fi
done

QUEUE_PREFIX="aft-quota-lambda-dlq-${ACCOUNT_ID}"
for url in $(aws sqs list-queues --query "QueueUrls[]" --output text | tr ' ' '\n' | grep "$QUEUE_PREFIX" 2>/dev/null || echo ""); do
    if [[ -n "$url" ]]; then
        echo "Deleting SQS queue: $url"
        aws sqs delete-queue --queue-url "$url" || echo "Could not delete queue $url"
    fi
done

for arn in $(aws sns list-topics --query "Topics[].TopicArn" --output text | tr ' ' '\n' | grep "aft-quota-notifications-${ACCOUNT_ID}" 2>/dev/null || echo ""); do
    if [[ -n "$arn" ]]; then
        echo "Deleting SNS topic: $arn"
        aws sns delete-topic --topic-arn "$arn" || echo "Could not delete topic $arn"
    fi
done

for alias in $(aws kms list-aliases --query "Aliases[].AliasName" --output text | tr ' ' '\n' | grep "alias/aft-quota-manager-logs-${ACCOUNT_ID}" 2>/dev/null || echo ""); do
    if [[ -n "$alias" ]]; then
        key_id=$(aws kms list-aliases --query \
            "Aliases[?AliasName=='${alias}'].TargetKeyId" --output text)
        echo "Deleting KMS alias: $alias"
        aws kms delete-alias --alias-name "$alias" || echo "Could not delete alias $alias"
        if [[ -n "$key_id" ]]; then
            echo "Scheduling deletion for key: $key_id"
            aws kms schedule-key-deletion --key-id "$key_id" --pending-window-in-days 7 \
                || echo "Could not schedule deletion for key $key_id"
        fi
    fi
done

for rule in $(aws events list-rules --query "Rules[].Name" --output text | tr ' ' '\n' | grep "aft-quota-monitor-${ACCOUNT_ID}" 2>/dev/null || echo ""); do
    if [[ -n "$rule" ]]; then
        echo "Removing targets & deleting EventBridge rule: $rule"
        aws events remove-targets --rule "$rule" --ids all || true
        aws events delete-rule --name "$rule" || echo "Could not delete rule $rule"
    fi
done

LOG_GROUPS=(
    "/aws/lambda/aft-quota-manager-${ACCOUNT_ID}"
    "/aws/lambda/notify_slack"
)
for lg in "${LOG_GROUPS[@]}"; do
    if aws logs describe-log-groups --log-group-name-prefix "$lg" \
        --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$lg"; then
        echo "Deleting log group: $lg"
        aws logs delete-log-group --log-group-name "$lg" || echo "Could not delete log group $lg"
    else
        echo "Log group $lg does not exist - skipping"
    fi
done

echo "Cleanup completed"

if ! aws lambda list-functions --max-items 1 >/dev/null 2>&1; then
    echo "ERROR: Lambda permissions missing"
    exit 1
fi

if ! aws service-quotas list-services --max-items 1 >/dev/null 2>&1; then
    echo "ERROR: Service Quotas permissions missing"
    exit 1
fi

echo "Prerequisites validated successfully"

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