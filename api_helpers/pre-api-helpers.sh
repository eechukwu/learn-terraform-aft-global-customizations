#!/bin/bash

echo "Executing Pre-API Helpers"

get_target_regions() {
    local regions
    
    regions=$(terraform output -raw quota_management_summary 2>/dev/null | jq -r '.target_regions[]' 2>/dev/null | tr '\n' ' ' || echo "")
    
    if [[ -n "$regions" ]]; then
        echo "$regions"
        return 0
    fi
    
    # Fallback - check if we can find a Lambda function to get regions from
    LAMBDA_FUNCTION=$(aws lambda list-functions \
        --query "Functions[?starts_with(FunctionName, 'aft-quota-manager')].FunctionName" \
        --output text | head -1 2>/dev/null || echo "")
    
    if [[ -n "$LAMBDA_FUNCTION" ]]; then
        # Try to get regions from Lambda environment or by invoking it
        regions=$(aws lambda invoke \
            --function-name "$LAMBDA_FUNCTION" \
            --payload '{"action":"check_status"}' \
            /tmp/pre_check_regions.json >/dev/null 2>&1 && \
            jq -r '.results | keys | join(" ")' /tmp/pre_check_regions.json 2>/dev/null || echo "")
        
        if [[ -n "$regions" ]]; then
            echo "$regions"
            return 0
        fi
    fi
    
    echo "us-east-1"
    return 0
}

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

TARGET_REGIONS=$(get_target_regions)
REGION_COUNT=$(echo $TARGET_REGIONS | wc -w)

echo "Target regions ($REGION_COUNT): $TARGET_REGIONS"
echo "Pre-API helpers completed successfully"