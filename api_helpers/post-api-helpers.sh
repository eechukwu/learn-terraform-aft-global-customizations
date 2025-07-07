#!/bin/bash

echo "Executing Post-API Helpers"

LAMBDA_FUNCTION=$(aws lambda list-functions --query 'Functions[?contains(FunctionName, `aft-quota-manager`)].FunctionName' --output text)

if [ -z "$LAMBDA_FUNCTION" ]; then
    echo "Error: No AFT quota manager Lambda function found"
    exit 1
fi

echo "Found Lambda function: $LAMBDA_FUNCTION"

TARGET_REGIONS=("us-east-1" "us-west-2" "eu-west-1" "eu-west-2" "ap-southeast-1")
echo "Target regions (${#TARGET_REGIONS[@]}): ${TARGET_REGIONS[*]}"

echo "Requesting quota increases across all ${#TARGET_REGIONS[@]} regions..."

PAYLOAD='{"action":"request_quotas"}'
RESPONSE_FILE=$(mktemp)

aws lambda invoke \
    --function-name "$LAMBDA_FUNCTION" \
    --qualifier live \
    --payload "$PAYLOAD" \
    --cli-binary-format raw-in-base64-out \
    "$RESPONSE_FILE"

if [ $? -eq 0 ]; then
    echo "Lambda invocation successful"
    echo "Response:"
    cat "$RESPONSE_FILE" | python3 -m json.tool
else
    echo "Lambda invocation failed"
    exit 1
fi

rm -f "$RESPONSE_FILE"
echo "Post-API helpers completed successfully"