#!/usr/bin/env bash
set -euo pipefail

echo "AFT Quota Monitor"

LAMBDA_PREFIX="aft-quota-manager"

get_target_regions() {
    local regions
    
    regions=$(terraform output -raw quota_management_summary 2>/dev/null | jq -r '.target_regions[]' 2>/dev/null | tr '\n' ' ' || echo "")
    
    if [[ -n "$regions" ]]; then
        echo "$regions"
        return 0
    fi
    
    # Fallback - get from Lambda function
    if [[ -n "${LAMBDA_FUNCTION:-}" ]]; then
        aws lambda invoke \
            --function-name "$LAMBDA_FUNCTION" \
            --qualifier "live" \
            --payload '{"action":"check_status"}' \
            /tmp/monitor_regions.json >/dev/null 2>&1
        
        regions=$(jq -r '.results | keys | join(" ")' /tmp/monitor_regions.json 2>/dev/null || echo "")
        
        if [[ -n "$regions" ]]; then
            echo "$regions"
            return 0
        fi
    fi
    
    echo "us-east-1"
    return 0
}

LAMBDA_FUNCTION=$(aws lambda list-functions \
    --query "Functions[?starts_with(FunctionName, '$LAMBDA_PREFIX')].FunctionName" \
    --output text | head -1)

if [[ -z "$LAMBDA_FUNCTION" ]]; then
    echo "ERROR: No Lambda function found"
    exit 1
fi

echo "Found function: $LAMBDA_FUNCTION"

TARGET_REGIONS=$(get_target_regions)
REGION_COUNT=$(echo $TARGET_REGIONS | wc -w)
echo "Monitoring $REGION_COUNT regions: $TARGET_REGIONS"

echo
echo "FUNCTION STATUS:"

FUNCTION_INFO=$(aws lambda get-function --function-name "$LAMBDA_FUNCTION" \
    --query 'Configuration.{State:State,Runtime:Runtime,Memory:MemorySize,Timeout:Timeout}' \
    --output json)

if command -v jq >/dev/null 2>&1; then
    echo "State:    $(echo "$FUNCTION_INFO" | jq -r '.State')"
    echo "Runtime:  $(echo "$FUNCTION_INFO" | jq -r '.Runtime')"
    echo "Memory:   $(echo "$FUNCTION_INFO" | jq -r '.MemorySize') MB"
    echo "Timeout:  $(echo "$FUNCTION_INFO" | jq -r '.Timeout') seconds"
fi

echo
echo "CURRENT QUOTA STATUS:"

aws lambda invoke \
    --function-name "$LAMBDA_FUNCTION" \
    --qualifier "live" \
    --payload '{"action":"check_status"}' \
    /tmp/monitor_status.json >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
    if command -v jq >/dev/null 2>&1; then
        printf "%-20s | %-8s | %s\n" "Region" "Value" "Status"
        printf "%-20s-+-%-8s-+-%s\n" "--------------------" "--------" "----------"
        
        jq -r '.results | to_entries[] | 
        "\(.key) | \(.value.current_value // \"Error\") | \(.value.status)"' \
        /tmp/monitor_status.json | \
        while IFS='|' read -r region value status; do
            printf "%-20s | %-8s | %s\n" "$region" "$value" "$status"
        done
        
        echo
        TARGET_COUNT=$(jq -r '[.results | to_entries[] | select(.value.current_value == 200)] | length' /tmp/monitor_status.json 2>/dev/null || echo "0")
        echo "Summary: $TARGET_COUNT/$REGION_COUNT regions have target quota (200)"
        
    else
        echo "Status check completed (install jq for formatted output)"
    fi
else
    echo "ERROR: Failed to check quota status"
fi

echo
echo "QUICK ACTIONS:"
echo "• View logs:      aws logs tail /aws/lambda/$LAMBDA_FUNCTION --follow"
echo "• Test function:  aws lambda invoke --function-name $LAMBDA_FUNCTION --qualifier live --payload '{\"action\":\"check_status\"}' test.json"

echo
echo "Monitoring completed" 