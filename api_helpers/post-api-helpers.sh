#!/bin/bash

echo "Executing Post-API Helpers"

LAMBDA_FUNCTION=$(aws lambda list-functions --query 'Functions[?contains(FunctionName, `aft-quota-manager`)].FunctionName' --output text)
if [ -z "$LAMBDA_FUNCTION" ]; then
    echo "Error: No AFT quota manager Lambda function found"
    exit 1
fi

echo "Found Lambda function: $LAMBDA_FUNCTION"

echo "Requesting quota increases..."
PAYLOAD='{"action":"request_quotas"}'
RESPONSE_FILE=$(mktemp)

aws lambda invoke \
    --function-name "$LAMBDA_FUNCTION" \
    --qualifier live \
    --payload "$PAYLOAD" \
    --cli-binary-format raw-in-base64-out \
    "$RESPONSE_FILE" >/dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "Lambda invocation successful"
    
    if command -v jq >/dev/null 2>&1; then
        # Extract the actual results from the nested JSON
        jq -r '.body | fromjson' "$RESPONSE_FILE" > /tmp/clean_response.json
        
        # Get services and display results
        SERVICES=$(jq -r '.results | to_entries[0].value | keys[]' /tmp/clean_response.json 2>/dev/null)
        
        if [ -n "$SERVICES" ]; then
            for service in $SERVICES; do
                echo ""
                echo "=== $(echo $service | tr '_' ' ' | tr '[:lower:]' '[:upper:]') ==="
                printf "%-15s %-10s %-10s %-20s\n" "Region" "Current" "Target" "Status"
                printf "%-15s %-10s %-10s %-20s\n" "---------------" "----------" "----------" "--------------------"
                
                jq -r --arg service "$service" '
                    .results | to_entries[] | 
                    [.key, (.value[$service].current_value // "N/A"), (.value[$service].target_value // "N/A"), (.value[$service].status // "error")] | @tsv
                ' /tmp/clean_response.json | \
                while IFS=$'\t' read -r region current target status; do
                    # Simplify status messages
                    case $status in
                        "already_sufficient") status="OK" ;;
                        "requested") status="REQUESTED" ;;
                        "error") status="PENDING_APPROVAL" ;;
                    esac
                    printf "%-15s %-10s %-10s %-20s\n" "$region" "$current" "$target" "$status"
                done
                
                # Count regions with target quota
                TARGET_VALUE=$(jq -r --arg service "$service" '.results | to_entries[0].value[$service].target_value' /tmp/clean_response.json 2>/dev/null)
                REGION_COUNT=$(jq -r '.results | keys | length' /tmp/clean_response.json)
                
                if [ "$TARGET_VALUE" != "null" ] && [ "$TARGET_VALUE" != "" ] && [ "$TARGET_VALUE" != "N/A" ]; then
                    OK_COUNT=$(jq -r --arg service "$service" --argjson target "$TARGET_VALUE" '
                        [.results | to_entries[] | select(.value[$service].current_value != null and .value[$service].current_value != "N/A" and (.value[$service].current_value | tonumber) >= $target)] | length
                    ' /tmp/clean_response.json 2>/dev/null)
                    echo "Summary: $OK_COUNT/$REGION_COUNT regions at target ($TARGET_VALUE)"
                else
                    # For cases where target is null/N/A, count how many have valid current values
                    VALID_COUNT=$(jq -r --arg service "$service" '
                        [.results | to_entries[] | select(.value[$service].current_value != null and .value[$service].current_value != "N/A")] | length
                    ' /tmp/clean_response.json 2>/dev/null)
                    echo "Summary: $VALID_COUNT/$REGION_COUNT regions processed (target unknown)"
                fi
            done
            
            echo ""
            echo "=== OVERALL STATUS ==="
            REGION_COUNT=$(jq -r '.results | keys | length' /tmp/clean_response.json)
            SERVICE_COUNT=$(echo "$SERVICES" | wc -w)
            
            TOTAL_OK=$(jq -r '
                [.results | to_entries[] | .value | to_entries[] | 
                select(.value.current_value != null and .value.current_value != "N/A" and .value.target_value != null and .value.target_value != "N/A" and (.value.current_value | tonumber) >= (.value.target_value | tonumber))] | length
            ' /tmp/clean_response.json 2>/dev/null)
            
            TOTAL_POSSIBLE=$((REGION_COUNT * SERVICE_COUNT))
            echo "Status: $TOTAL_OK/$TOTAL_POSSIBLE quotas at target across $REGION_COUNT regions"
            
            PENDING_COUNT=$(jq -r '
                [.results | to_entries[] | .value | to_entries[] | 
                select(.value.status == "error" or .value.status == "requested")] | length
            ' /tmp/clean_response.json 2>/dev/null)
            
            if [ "$PENDING_COUNT" -gt 0 ]; then
                echo "Note: $PENDING_COUNT quotas have requests pending approval"
            fi
            
        else
            echo "No quota data found"
        fi
        
        rm -f /tmp/clean_response.json
        
    else
        echo "Install jq for formatted output"
        cat "$RESPONSE_FILE"
    fi
    
else
    echo "Lambda invocation failed"
    exit 1
fi

rm -f "$RESPONSE_FILE"

echo ""
echo "=== MONITORING ==="
echo "Check status: aws lambda invoke --function-name $LAMBDA_FUNCTION --payload '{\"action\":\"monitor_requests\"}' --cli-binary-format raw-in-base64-out response.json"
echo "View logs: aws logs tail /aws/lambda/$LAMBDA_FUNCTION --follow"

echo "Post-API helpers completed"