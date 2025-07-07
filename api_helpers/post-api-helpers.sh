#!/bin/bash

# post-api-helpers.sh - Fixed version for AFT quota management

echo "Executing Post-API Helpers"

# Find the Lambda function
LAMBDA_FUNCTION=$(aws lambda list-functions --query 'Functions[?contains(FunctionName, `aft-quota-manager`)].FunctionName' --output text)

if [ -z "$LAMBDA_FUNCTION" ]; then
    echo "Error: No AFT quota manager Lambda function found"
    exit 1
fi

echo "Found Lambda function: $LAMBDA_FUNCTION"

# Define target regions (should match your locals.tf configuration)
TARGET_REGIONS=("us-east-1" "us-west-2" "eu-west-1" "eu-west-2" "ap-southeast-1")
echo "Target regions (${#TARGET_REGIONS[@]}): ${TARGET_REGIONS[*]}"

echo "Checking quota status across all ${#TARGET_REGIONS[@]} regions..."

# Create the JSON payload properly
PAYLOAD='{"action":"check_status"}'

# Create a temporary file for the response
RESPONSE_FILE=$(mktemp)

# Invoke the Lambda function with proper payload handling
echo "Invoking Lambda function with payload: $PAYLOAD"

aws lambda invoke \
    --function-name "$LAMBDA_FUNCTION" \
    --qualifier live \
    --payload "$PAYLOAD" \
    --cli-binary-format raw-in-base64-out \
    "$RESPONSE_FILE"

# Check if the invocation was successful
if [ $? -eq 0 ]; then
    echo "Lambda invocation successful"
    echo "Response:"
    
    # Pretty print the JSON response
    if command -v python3 &> /dev/null; then
        cat "$RESPONSE_FILE" | python3 -m json.tool
    else
        cat "$RESPONSE_FILE"
    fi
    
    # Extract and display summary information
    echo ""
    echo "=== QUOTA STATUS SUMMARY ==="
    
    # Check if jq is available for better JSON parsing
    if command -v jq &> /dev/null; then
        SUCCESS_RATE=$(cat "$RESPONSE_FILE" | jq -r '.summary.success_rate // "N/A"')
        SUCCESSFUL_REGIONS=$(cat "$RESPONSE_FILE" | jq -r '.summary.successful_regions // "N/A"')
        TOTAL_REGIONS=$(cat "$RESPONSE_FILE" | jq -r '.summary.total_regions // "N/A"')
        
        echo "Success Rate: $SUCCESS_RATE"
        echo "Successful Regions: $SUCCESSFUL_REGIONS/$TOTAL_REGIONS"
        
        # Show any errors
        ERROR_COUNT=$(cat "$RESPONSE_FILE" | jq -r '[.results[] | select(.status == "error")] | length')
        if [ "$ERROR_COUNT" -gt 0 ]; then
            echo "Errors found in $ERROR_COUNT regions:"
            cat "$RESPONSE_FILE" | jq -r '.results | to_entries[] | select(.value.status == "error") | "  - \(.key): \(.value.error)"'
        fi
    else
        echo "Install jq for better JSON parsing and summary display"
    fi
    
else
    echo "Lambda invocation failed"
    echo "Response file contents:"
    cat "$RESPONSE_FILE"
    exit 1
fi

# Clean up
rm -f "$RESPONSE_FILE"

echo "Post-API helpers completed successfully"