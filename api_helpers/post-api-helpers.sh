#!/bin/bash
# Multi-Region Security Group Quota Automation - Post-API Validation Script
# This script validates quota requests across multiple AWS regions

set -e

# Configuration
SCRIPT_NAME="AFT Multi-Region Quota Validation"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
QUOTA_SERVICE_CODE="vpc"
QUOTA_CODE="L-0EA8095F"
TARGET_QUOTA_VALUE=200
VALIDATION_REPORT="/tmp/aft-multiregion-quota-validation-report.json"

# Default regions to check (can be overridden)
DEFAULT_REGIONS=("us-east-1" "eu-west-2" "ap-southeast-1")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to get account information
get_account_info() {
    local region=$1
    local account_info
    
    if account_info=$(aws sts get-caller-identity --region "$region" 2>/dev/null); then
        echo "$account_info"
        return 0
    else
        log_error "Failed to get account information for region $region"
        return 1
    fi
}

# Function to validate quota in a specific region
validate_region_quota() {
    local region=$1
    local validation_result="UNKNOWN"
    local current_quota="N/A"
    local recent_requests=0
    local quota_status="UNKNOWN"
    
    log_info "Validating quota for region: $region"
    
    # Get current quota value
    if current_quota_info=$(aws service-quotas get-service-quota \
        --service-code "$QUOTA_SERVICE_CODE" \
        --quota-code "$QUOTA_CODE" \
        --region "$region" 2>/dev/null); then
        
        current_quota=$(echo "$current_quota_info" | jq -r '.Quota.Value')
        log_info "Current quota in $region: $current_quota"
        
        # Check if quota is already at target value
        if (( $(echo "$current_quota >= $TARGET_QUOTA_VALUE" | bc -l) )); then
            validation_result="SUCCESS"
            quota_status="AT_TARGET"
            log_success "Quota in $region is at target value ($current_quota)"
        else
            quota_status="BELOW_TARGET"
            log_warning "Quota in $region is below target ($current_quota < $TARGET_QUOTA_VALUE)"
        fi
    else
        log_error "Failed to get current quota for region $region"
        current_quota="ERROR"
    fi
    
    # Check for recent quota requests
    if recent_requests_info=$(aws service-quotas list-requested-service-quota-change-history \
        --service-code "$QUOTA_SERVICE_CODE" \
        --region "$region" \
        --max-results 10 2>/dev/null); then
        
        # Count recent requests for our specific quota
        recent_requests=$(echo "$recent_requests_info" | jq -r \
            ".RequestedQuotas[] | select(.QuotaCode == \"$QUOTA_CODE\") | .Id" | wc -l)
        
        if [ "$recent_requests" -gt 0 ]; then
            log_info "Found $recent_requests recent quota request(s) for $region"
            
            # Get the most recent request status
            latest_request=$(echo "$recent_requests_info" | jq -r \
                ".RequestedQuotas[] | select(.QuotaCode == \"$QUOTA_CODE\") | .Status" | head -1)
            
            if [ "$latest_request" = "PENDING" ]; then
                validation_result="PENDING"
                quota_status="REQUEST_PENDING"
                log_info "Latest request for $region is PENDING"
            elif [ "$latest_request" = "APPROVED" ]; then
                validation_result="SUCCESS"
                quota_status="REQUEST_APPROVED"
                log_success "Latest request for $region was APPROVED"
            elif [ "$latest_request" = "DENIED" ]; then
                validation_result="FAILED"
                quota_status="REQUEST_DENIED"
                log_error "Latest request for $region was DENIED"
            fi
        else
            log_warning "No recent quota requests found for region $region"
            if [ "$quota_status" = "BELOW_TARGET" ]; then
                validation_result="MISSING_REQUEST"
            fi
        fi
    else
        log_error "Failed to get quota request history for region $region"
    fi
    
    # Store region results
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

# Function to generate comprehensive validation report
generate_validation_report() {
    local overall_status="UNKNOWN"
    local successful_regions=0
    local failed_regions=0
    local pending_regions=0
    local total_regions=${#region_results[@]}
    
    log_info "Generating multi-region validation report..."
    
    # Count results by type
    for region in "${!region_results[@]}"; do
        result=$(echo "${region_results[$region]}" | jq -r '.validation_result')
        case "$result" in
            "SUCCESS")
                ((successful_regions++))
                ;;
            "PENDING")
                ((pending_regions++))
                ;;
            "FAILED"|"MISSING_REQUEST")
                ((failed_regions++))
                ;;
        esac
    done
    
    # Determine overall status
    if [ "$successful_regions" -eq "$total_regions" ]; then
        overall_status="SUCCESS"
    elif [ "$failed_regions" -gt 0 ]; then
        overall_status="FAILED"
    elif [ "$pending_regions" -gt 0 ]; then
        overall_status="PENDING"
    else
        overall_status="PARTIAL"
    fi
    
    # Get account info
    account_info=$(get_account_info "${DEFAULT_REGIONS[0]}")
    account_id=$(echo "$account_info" | jq -r '.Account')
    account_arn=$(echo "$account_info" | jq -r '.Arn')
    
    # Generate JSON report
    local report_data=$(jq -n \
        --arg timestamp "$TIMESTAMP" \
        --arg account_id "$account_id" \
        --arg account_arn "$account_arn" \
        --arg service_code "$QUOTA_SERVICE_CODE" \
        --arg quota_code "$QUOTA_CODE" \
        --argjson target_quota "$TARGET_QUOTA_VALUE" \
        --arg overall_status "$overall_status" \
        --argjson successful_regions "$successful_regions" \
        --argjson failed_regions "$failed_regions" \
        --argjson pending_regions "$pending_regions" \
        --argjson total_regions "$total_regions" \
        --arg aft_automation "multi-region-security-group-quota" \
        --arg version "2.0" \
        '{
            timestamp: $timestamp,
            account_id: $account_id,
            account_arn: $account_arn,
            service_code: $service_code,
            quota_code: $quota_code,
            target_quota: $target_quota,
            overall_status: $overall_status,
            region_summary: {
                successful_regions: $successful_regions,
                failed_regions: $failed_regions,
                pending_regions: $pending_regions,
                total_regions: $total_regions
            },
            aft_automation: $aft_automation,
            version: $version
        }')
    
    # Add regional details
    local regional_details="[]"
    for region in "${!region_results[@]}"; do
        regional_details=$(echo "$regional_details" | jq ". += [${region_results[$region]}]")
    done
    
    report_data=$(echo "$report_data" | jq --argjson regional_details "$regional_details" '. + {regional_details: $regional_details}')
    
    # Save report
    echo "$report_data" > "$VALIDATION_REPORT"
    log_success "Validation report saved to: $VALIDATION_REPORT"
    
    # Display summary
    log_info "Multi-Region Validation Summary:"
    log_info "  Total Regions: $total_regions"
    log_info "  Successful: $successful_regions"
    log_info "  Pending: $pending_regions"
    log_info "  Failed: $failed_regions"
    log_info "  Overall Status: $overall_status"
    
    echo "$report_data"
}

# Main execution
main() {
    log_info "Starting $SCRIPT_NAME"
    log_info "Timestamp: $TIMESTAMP"
    
    # Initialize associative array for region results
    declare -A region_results
    
    # Get regions to validate (from environment or use defaults)
    if [ -n "$AFT_TARGET_REGIONS" ]; then
        IFS=',' read -ra REGIONS <<< "$AFT_TARGET_REGIONS"
    else
        REGIONS=("${DEFAULT_REGIONS[@]}")
    fi
    
    log_info "Validating quota automation across ${#REGIONS[@]} regions..."
    
    # Validate each region
    for region in "${REGIONS[@]}"; do
        validate_region_quota "$region"
    done
    
    # Generate and display final report
    validation_report=$(generate_validation_report)
    
    log_info "Validation Report:"
    echo "$validation_report" | jq '.'
    
    log_info "$SCRIPT_NAME completed"
}

# Execute main function
main "$@"