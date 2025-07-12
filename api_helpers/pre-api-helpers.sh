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

echo "Cleaning up existing resources..."

# 1. Delete IAM policies
POLICIES=(
    "aft-quota-manager-${ACCOUNT_ID}-logs"
    "aft-quota-manager-${ACCOUNT_ID}-dl"
    "aft-quota-manager-${ACCOUNT_ID}"
    "lambda-notify_slack"
)
for policy in "${POLICIES[@]}"; do
    ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${policy}"
    if aws iam get-policy --policy-arn "$ARN" >/dev/null 2>&1; then
        echo "Deleting policy: $policy"
        aws iam delete-policy --policy-arn "$ARN" || echo "Could not delete policy $policy"
    fi
done

# 2. Delete Lambda functions
LAMBDA_FUNCTIONS=(
    "aft-quota-manager-${ACCOUNT_ID}"
    "notify_slack"
)
for fn in "${LAMBDA_FUNCTIONS[@]}"; do
    if aws lambda get-function --function-name "$fn" >/dev/null 2>&1; then
        echo "Deleting Lambda function: $fn"
        aws lambda delete-function --function-name "$fn" || echo "Could not delete Lambda $fn"
    fi
done

# 3. Delete IAM roles
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
    fi
done

# 4. Delete SQS queues
QUEUE_PREFIX="aft-quota-lambda-dlq-${ACCOUNT_ID}"
for url in $(aws sqs list-queues --query "QueueUrls[]" --output text | tr ' ' '\n' | grep "$QUEUE_PREFIX"); do
    echo "Deleting SQS queue: $url"
    aws sqs delete-queue --queue-url "$url" || echo "Could not delete queue $url"
done

# 5. Delete SNS topics
for arn in $(aws sns list-topics --query "Topics[].TopicArn" --output text | tr ' ' '\n' | grep "aft-quota-notifications-${ACCOUNT_ID}"); do
    echo "Deleting SNS topic: $arn"
    aws sns delete-topic --topic-arn "$arn" || echo "Could not delete topic $arn"
done

# 6. Delete KMS aliases & schedule key deletion
for alias in $(aws kms list-aliases --query "Aliases[].AliasName" --output text | tr ' ' '\n' | grep "alias/aft-quota-manager-logs-${ACCOUNT_ID}"); do
    key_id=$(aws kms list-aliases --query \
        "Aliases[?AliasName=='${alias}'].TargetKeyId" --output text)
    echo "Deleting KMS alias: $alias"
    aws kms delete-alias --alias-name "$alias" || echo "Could not delete alias $alias"
    echo "Scheduling deletion for key: $key_id"
    aws kms schedule-key-deletion --key-id "$key_id" --pending-window-in-days 7 \
        || echo "Could not schedule deletion for key $key_id"
done

# 7. Delete CloudWatch EventBridge rules
for rule in $(aws events list-rules --query "Rules[].Name" --output text | tr ' ' '\n' | grep "aft-quota-monitor-${ACCOUNT_ID}"); do
    echo "Removing targets & deleting EventBridge rule: $rule"
    aws events remove-targets --rule "$rule" --ids all || true
    aws events delete-rule --name "$rule" || echo "Could not delete rule $rule"
done

# 8. Delete CloudWatch metric alarms
for alarm in $(aws cloudwatch describe-alarms --query "MetricAlarms[].AlarmName" --output text | tr ' ' '\n' | grep "aft-quota-manager-"); do
    echo "Deleting CloudWatch alarm: $alarm"
    aws cloudwatch delete-alarms --alarm-names "$alarm" || echo "Could not delete alarm $alarm"
done

# 9. Delete CloudWatch log groups
LOG_GROUPS=(
    "/aws/lambda/aft-quota-manager-${ACCOUNT_ID}"
    "/aws/lambda/notify_slack"
)
for lg in "${LOG_GROUPS[@]}"; do
    if aws logs describe-log-groups --log-group-name-prefix "$lg" \
        --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$lg"; then
        echo "Deleting log group: $lg"
        aws logs delete-log-group --log-group-name "$lg" || echo "Could not delete log group $lg"
    fi
done

echo "Cleanup completed - ready for fresh deployment"
echo "Pre-API helpers completed successfully"