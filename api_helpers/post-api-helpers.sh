#!/usr/bin/env bash
set -euo pipefail

echo "Executing Post-API Helpers"

find_lambda_function() {
    local lambda_name
    
    lambda_name=$(terraform output -raw lambda_quota_manager 2>/dev/null | jq -r '.function_name' 2>/dev/null || echo "")
    
    if [[ -n "$lambda_name" ]]; then
        echo "$lambda_name"
        return 0
    fi
    
    lambda_name=$(aws lambda list-functions \
        --query "Functions[?starts_with(FunctionName, 'aft-quota-manager')].FunctionName" \
        --output text | head -1)
    
    if [[ -n "$lambda_name" ]]; then
        echo "$lambda_name"
        return 0
    fi
    
    return 1
}

get_target_regions() {
    local regions
    
    regions=$(terraform output -raw quota_management_summary 2>/dev/null | jq -r '.target_regions[]' 2>/dev/null | tr '\n' ' ' || echo "")
    
    if [[ -n "$regions" ]]; then
        echo "$regions"
        return 0
    fi
    
    # If terraform output fails, get regions from Lambda environment
    regions=$(aws lambda get-function --function-name "$LAMBDA_FUNCTION" 2>/dev/null | \
        jq -r '.Configuration.Environment.Variables.REGIONS // empty' 2>/dev/null || echo "")
    
    if [[ -n "$regions" ]]; then
        echo "$regions"
        return 0
    fi
    
    # Final fallback - invoke Lambda to get its default regions
    aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION" \
        --qualifier "live" \
        --payload '{"action":"check_status"}' \
        /tmp/get_regions.json >/dev/null 2>&1
    
    regions=$(jq -r '.results | keys | join(" ")' /tmp/get_regions.json 2>/dev/null || echo "")
    
    if [[ -n "$regions" ]]; then
        echo "$regions"
        return 0
    fi
    
    echo "us-east-1"
    return 0
}

LAMBDA_FUNCTION=$(find_lambda_function)

if [[ -z "$LAMBDA_FUNCTION" ]]; then
    echo "ERROR: Could not find Lambda function"
    exit 1
fi

echo "Found Lambda function: $LAMBDA_FUNCTION"

TARGET_REGIONS=$(get_target_regions)
REGION_COUNT=$(echo $TARGET_REGIONS | wc -w)
echo "Target regions ($REGION_COUNT): $TARGET_REGIONS"

FUNCTION_STATE=$(aws lambda get-function --function-name "$LAMBDA_FUNCTION" --query 'Configuration.State' --output text)

if [[ "$FUNCTION_STATE" != "Active" ]]; then
    echo "WARNING: Lambda function state is: $FUNCTION_STATE"
    echo "Waiting for function to become active..."
    
    for i in {1..30}; do
        sleep 2
        FUNCTION_STATE=$(aws lambda get-function --function-name "$LAMBDA_FUNCTION" --query 'Configuration.State' --output text)
        if [[ "$FUNCTION_STATE" == "Active" ]]; then
            echo "Lambda function is now active"
            break
        fi
        if [[ $i -eq 30 ]]; then
            echo "ERROR: Lambda function did not become active within 60 seconds"
            exit 1
        fi
    done
fi

echo "Checking quota status across all $REGION_COUNT regions..."
aws lambda invoke \
    --function-name "$LAMBDA_FUNCTION" \
    --qualifier "live" \
    --payload '{"action":"check_status"}' \
    /tmp/quota_check_response.json > /dev/null

if [[ $? -eq 0 ]]; then
    echo "Quota status check completed successfully"
    
    if command -v jq >/dev/null 2>&1; then
        echo
        echo "EXECUTION SUMMARY:"
        
        jq -r '.summary | 
        "Total regions: \(.total_regions)
        Successful: \(.successful_regions)  
        Failed: \(.failed_regions)
        Success rate: \(.success_rate)
        Execution time: \(.execution_time_seconds)s"' /tmp/quota_check_response.json 2>/dev/null || echo "Summary not available"
        
        echo
        echo "REGIONAL STATUS:"
        printf "%-20s | %-10s | %-8s\n" "Region" "Status" "Value"
        printf "%-20s-+-%-10s-+-%-8s\n" "--------------------" "----------" "--------"
        
        jq -r '.results | to_entries[] | 
        "\(.key) | \(.value.status // "unknown") | \(.value.current_value // "N/A")"' \
        /tmp/quota_check_response.json 2>/dev/null | \
        while IFS='|' read -r region status value; do
            printf "%-20s | %-10s | %-8s\n" "$region" "$status" "$value"
        done
        
        TARGET_COUNT=$(jq -r '[.results | to_entries[] | select(.value.current_value == 200)] | length' /tmp/quota_check_response.json 2>/dev/null || echo "0")
        
        if [[ "$TARGET_COUNT" == "$REGION_COUNT" ]]; then
            echo "All regions have target quota of 200"
        else
            PENDING_COUNT=$((REGION_COUNT - TARGET_COUNT))
            echo "$PENDING_COUNT regions may need quota increases"
        fi
        
    else
        echo "Install jq for detailed output formatting"
    fi
    
    echo "Post-API helpers completed successfully"
    exit 0
else
    echo "ERROR: Lambda quota check failed"
    exit 1
fi