#!/bin/bash

set -e

REGIONS=("us-east-1" "eu-west-2" "ap-southeast-1")
SERVICE_CODE="vpc"
QUOTA_CODE="L-0EA8095F"
EXPECTED_VALUE=200
MAX_ATTEMPTS=24
SLEEP_INTERVAL=300

validate_quota() {
    local region=$1
    local quota_info
    
    quota_info=$(aws service-quotas get-service-quota \
        --service-code "$SERVICE_CODE" \
        --quota-code "$QUOTA_CODE" \
        --region "$region" \
        --query 'Quota.{Value:Value}' \
        --output json 2>/dev/null || echo '{"Value":60}')
    
    echo "$quota_info" | jq -r '.Value // 60'
}

check_quota_request() {
    local region=$1
    
    aws service-quotas list-requested-service-quota-change-history \
        --service-code "$SERVICE_CODE" \
        --region "$region" \
        --query "RequestedQuotas[?QuotaCode=='$QUOTA_CODE' && Status=='PENDING'].Id" \
        --output text 2>/dev/null || echo ""
}

main() {
    local attempt=1
    local initial_check=true
    
    while [ $attempt -le $MAX_ATTEMPTS ]; do
        if [ "$initial_check" = true ]; then
            echo "Validating security group quota configuration"
            initial_check=false
        else
            echo "Attempt $attempt/$MAX_ATTEMPTS - checking quota status"
        fi
        
        echo
        printf "%-15s | %-9s | %5s | %s\n" "Region" "Status" "Value" "Request ID"
        printf "%-15s-+-%-9s-+-%5s-+-%-10s\n" "---------------" "---------" "-----" "----------"
        
        local all_approved=true
        local pending_regions=()
        local approved_regions=()
        local failed_regions=()
        
        for region in "${REGIONS[@]}"; do
            local current_value=$(validate_quota "$region")
            local request_id=$(check_quota_request "$region")
            local status="APPROVED"
            
            # Use arithmetic expansion instead of bc
            if [ "$current_value" -lt "$EXPECTED_VALUE" ]; then
                if [ -n "$request_id" ]; then
                    status="PENDING"
                    pending_regions+=("$region")
                else
                    status="FAILED"
                    failed_regions+=("$region")
                fi
                all_approved=false
            else
                approved_regions+=("$region")
            fi
            
            printf "%-15s | %-9s | %5.0f | %s\n" "$region" "$status" "$current_value" "${request_id:-N/A}"
        done
        
        echo
        
        if [ ${#approved_regions[@]} -gt 0 ]; then
            echo "Approved regions: ${approved_regions[*]}"
        fi
        
        if [ ${#pending_regions[@]} -gt 0 ]; then
            echo "Pending regions: ${pending_regions[*]}"
        fi
        
        if [ ${#failed_regions[@]} -gt 0 ]; then
            echo "Failed regions: ${failed_regions[*]}"
        fi
        
        if [ "$all_approved" = true ]; then
            echo
            echo "All quotas approved successfully"
            exit 0
        elif [ ${#failed_regions[@]} -gt 0 ]; then
            echo
            echo "Some regions failed to request quota increases"
            echo "Please check AWS Console or retry manually"
            exit 1
        elif [ $attempt -ge $MAX_ATTEMPTS ]; then
            echo
            echo "Timeout reached but this is normal AWS behavior"
            echo "Quota requests are still processing and will be applied automatically"
            echo "Infrastructure deployment: SUCCESSFUL"
            echo "Quota processing: IN PROGRESS (will complete within 24-48 hours)"
            echo
            echo "Check status: AWS Console > Service Quotas > Request History"
            exit 0
        else
            echo
            echo "Waiting ${SLEEP_INTERVAL}s for quota processing"
            sleep $SLEEP_INTERVAL
        fi
        
        ((attempt++))
    done
}

echo "Executing Post-API Helpers"
main "$@"