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
    "$RESPONSE_FILE"

if [ $? -eq 0 ]; then
    echo "Lambda invocation successful"
    echo "Response:"
    cat "$RESPONSE_FILE" | python3 -m json.tool
    
    echo ""
    echo "=== QUOTA STATUS MONITORING ==="
    
    echo "Checking current quota status..."
    STATUS_PAYLOAD='{"action":"monitor_requests"}'
    STATUS_FILE=$(mktemp)
    
    aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION" \
        --qualifier live \
        --payload "$STATUS_PAYLOAD" \
        --cli-binary-format raw-in-base64-out \
        "$STATUS_FILE"
    
    if [ $? -eq 0 ]; then
        echo "Current quota status:"
        if command -v jq >/dev/null 2>&1; then
            SERVICES=$(jq -r '.results | to_entries[0].value | keys[]' "$STATUS_FILE" 2>/dev/null)
            
            for service in $SERVICES; do
                echo ""
                echo "=== $service ==="
                printf "%-20s | %-8s | %s\n" "Region" "Value" "Status"
                printf "%-20s-+-%-8s-+-%s\n" "--------------------" "--------" "----------"
                
                jq -r --arg service "$service" '
                    .results | to_entries[] | 
                    [$service, .key, (.value[$service].current_value // "Error"), (.value[$service].status // "Error")] | @tsv
                ' "$STATUS_FILE" | \
                while IFS=$'\t' read -r service_name region value status; do
                    printf "%-20s | %-8s | %s\n" "$region" "$value" "$status"
                done
                
                REGION_COUNT=$(jq -r '.results | keys | length' "$STATUS_FILE")
                SUCCESSFUL_COUNT=$(jq -r --arg service "$service" '
                    .results | to_entries[] | 
                    select(.value[$service].current_value >= 
                        (if $service == "security_groups" then 200
                         elif $service == "iam_roles" then 5000
                         elif $service == "iam_policies" then 1500
                         else 0 end))
                ' "$STATUS_FILE" 2>/dev/null | wc -l)
                
                TARGET_VALUE=$(case "$service" in
                    "security_groups") echo "200" ;;
                    "iam_roles") echo "5000" ;;
                    "iam_policies") echo "1500" ;;
                    *) echo "Unknown" ;;
                esac)
                
                echo "Summary: $SUCCESSFUL_COUNT/$REGION_COUNT regions have target quota ($TARGET_VALUE)"
            done
            
            echo ""
            echo "=== OVERALL SUMMARY ==="
            REGION_COUNT=$(jq -r '.results | keys | length' "$STATUS_FILE")
            SERVICE_COUNT=$(echo "$SERVICES" | wc -w)
            TOTAL_SERVICES=$((REGION_COUNT * SERVICE_COUNT))
            
            TOTAL_SUCCESSFUL=$(jq -r '
                .results | to_entries[] | .value | to_entries[] | 
                select(.value.current_value >= 
                    (if .key == "security_groups" then 200
                     elif .key == "iam_roles" then 5000
                     elif .key == "iam_policies" then 1500
                     else 0 end))
            ' "$STATUS_FILE" 2>/dev/null | wc -l)
            
            echo "Total: $TOTAL_SUCCESSFUL/$TOTAL_SERVICES services have target quotas"
            echo "Regions: $REGION_COUNT, Services: $SERVICE_COUNT"
        else
            echo "Status check completed (install jq for formatted output)"
            cat "$STATUS_FILE" | python3 -m json.tool
        fi
    else
        echo "ERROR: Failed to check quota status"
    fi
    
    rm -f "$STATUS_FILE"
    
    echo ""
    echo "=== MONITORING COMMANDS ==="
    echo "To monitor approval status:"
    echo "aws lambda invoke --function-name $LAMBDA_FUNCTION --qualifier live --payload '{\"action\":\"monitor_requests\"}' --cli-binary-format raw-in-base64-out response.json"
    echo ""
    echo "To view logs:"
    echo "aws logs tail /aws/lambda/$LAMBDA_FUNCTION --follow"
else
    echo "Lambda invocation failed"
    exit 1
fi

rm -f "$RESPONSE_FILE"

SSM_PARAM="/aft/slack/quota-manager-bot-token"
if aws ssm get-parameter --name "$SSM_PARAM" >/dev/null 2>&1; then
    PARAM_VALUE=$(aws ssm get-parameter --name "$SSM_PARAM" --with-decryption --query 'Parameter.Value' --output text 2>/dev/null)
    if [[ "$PARAM_VALUE" == *"dummy-token"* ]]; then
        echo ""
        echo "To enable Slack notifications:"
        echo "aws ssm put-parameter --name '$SSM_PARAM' --value 'xoxb-your-slack-bot-token' --type 'SecureString' --overwrite"
    fi
fi

echo "Post-API helpers completed" 