#!/bin/bash
# Post-API validation script for AFT quota automation

set -e

# Configuration
QUOTA_SERVICE_CODE="vpc"
QUOTA_CODE="L-0EA8095F"
TARGET_QUOTA_VALUE=200
VALIDATION_REPORT="/tmp/quota-validation-report.json"
DEFAULT_REGIONS=("us-east-1" "eu-west-2" "ap-southeast-1")

# Get account information
get_account_info() {
    local region=$1
    aws sts get-caller-identity --region "$region" 2>/dev/null
}

# Validate quota in region
validate_region_quota() {
    local region=$1
    local validation_result="UNKNOWN"
    local current_quota="N/A"
    local quota_status="UNKNOWN"
    
    echo "[INFO] Validating quota for region: $region"
    
    # Get current quota
    if current_quota_info=$(aws service-quotas get-service-quota \
        --service-code "$QUOTA_SERVICE_CODE" \
        --quota-code "$QUOTA_CODE" \
        --region "$region" 2>/dev/null); then
        
        current_quota=$(echo "$current_quota_info" | jq -r '.Quota.Value')
        echo "[INFO] Current quota in $region: $current_quota"
        
        # Check if quota meets target
        current_quota_int=${current_quota%.*}
        target_quota_int=${TARGET_QUOTA_VALUE%.*}
        
        if [[ $current_quota_int -ge $target_quota_int ]]; then
            validation_result="SUCCESS"
            quota_status="AT_TARGET"
            echo "[SUCCESS] Quota in $region is at target value"
        else
            quota_status="BELOW_TARGET"
            echo "[WARNING] Quota in $region is below target"
        fi
    else
        echo "[ERROR] Failed to get quota for region $region"
        current_quota="ERROR"
    fi
    
    # Check recent requests
    if recent_requests_info=$(aws service-quotas list-requested-service-quota-change-history \
        --service-code "$QUOTA_SERVICE_CODE" \
        --region "$region" \
        --max-results 10 2>/dev/null); then
        
        recent_requests=$(echo "$recent_requests_info" | jq -r \
            ".RequestedQuotas[] | select(.QuotaCode == \"$QUOTA_CODE\") | .Id" | wc -l)
        
        if [ "$recent_requests" -gt 0 ]; then
            echo "[INFO] Found $recent_requests recent quota request(s)"
            
            latest_request=$(echo "$recent_requests_info" | jq -r \
                ".RequestedQuotas[] | select(.QuotaCode == \"$QUOTA_CODE\") | .Status" | head -1)
            
            case "$latest_request" in
                "PENDING")
                    validation_result="PENDING"
                    quota_status="REQUEST_PENDING"
                    ;;
                "APPROVED")
                    validation_result="SUCCESS"
                    quota_status="REQUEST_APPROVED"
                    ;;
                "DENIED")
                    validation_result="FAILED"
                    quota_status="REQUEST_DENIED"
                    ;;
            esac
        fi
    fi
    
    region_results["$region"]=$(jq -n \
        --arg region "$region" \
        --arg validation_result "$validation_result" \
        --arg current_quota "$current_quota" \
        --arg quota_status "$quota_status" \
        --argjson recent_requests "$recent_requests" \
        '{
            region: $region,
            validation_result: $validation_result,
            current_quota: $current_quota,
            quota_status: $quota_status,
            recent_requests: $recent_requests
        }')
    
    return 0
}

# Generate validation report
generate_validation_report() {
    local successful_regions=0
    local failed_regions=0
    local pending_regions=0
    local total_regions=${#region_results[@]}
    
    # Count results
    for region in "${!region_results[@]}"; do
        result=$(echo "${region_results[$region]}" | jq -r '.validation_result')
        case "$result" in
            "SUCCESS") ((successful_regions++)) ;;
            "PENDING") ((pending_regions++)) ;;
            "FAILED"|"MISSING_REQUEST") ((failed_regions++)) ;;
        esac
    done
    
    # Determine overall status
    local overall_status="UNKNOWN"
    if [ "$successful_regions" -eq "$total_regions" ]; then
        overall_status="SUCCESS"
    elif [ "$failed_regions" -gt 0 ]; then
        overall_status="FAILED"
    elif [ "$pending_regions" -gt 0 ]; then
        overall_status="PENDING"
    fi
    
    # Get account info
    account_info=$(get_account_info "${DEFAULT_REGIONS[0]}")
    account_id=$(echo "$account_info" | jq -r '.Account')
    
    # Generate report
    local report_data=$(jq -n \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg account_id "$account_id" \
        --arg service_code "$QUOTA_SERVICE_CODE" \
        --arg quota_code "$QUOTA_CODE" \
        --argjson target_quota "$TARGET_QUOTA_VALUE" \
        --arg overall_status "$overall_status" \
        --argjson successful_regions "$successful_regions" \
        --argjson failed_regions "$failed_regions" \
        --argjson pending_regions "$pending_regions" \
        --argjson total_regions "$total_regions" \
        '{
            timestamp: $timestamp,
            account_id: $account_id,
            service_code: $service_code,
            quota_code: $quota_code,
            target_quota: $target_quota,
            overall_status: $overall_status,
            region_summary: {
                successful_regions: $successful_regions,
                failed_regions: $failed_regions,
                pending_regions: $pending_regions,
                total_regions: $total_regions
            }
        }')
    
    # Add regional details
    local regional_details="[]"
    for region in "${!region_results[@]}"; do
        regional_details=$(echo "$regional_details" | jq ". += [${region_results[$region]}]")
    done
    
    report_data=$(echo "$report_data" | jq --argjson regional_details "$regional_details" '. + {regional_details: $regional_details}')
    
    echo "$report_data" > "$VALIDATION_REPORT"
    echo "$report_data"
}

# Main
main() {
    declare -A region_results
    
    if [ -n "$AFT_TARGET_REGIONS" ]; then
        IFS=',' read -ra REGIONS <<< "$AFT_TARGET_REGIONS"
    else
        REGIONS=("${DEFAULT_REGIONS[@]}")
    fi
    
    echo "[INFO] Validating ${#REGIONS[@]} regions"
    
    for region in "${REGIONS[@]}"; do
        validate_region_quota "$region"
    done
    
    validation_report=$(generate_validation_report)
    
    if echo "$validation_report" | jq empty 2>/dev/null; then
        echo "$validation_report" | jq '.'
    fi
    
    exit 0
}

main "$@"