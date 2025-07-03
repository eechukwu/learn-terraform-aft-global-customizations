#!/bin/bash
# post-api-helpers.sh - AFT post-deployment validation for Security Group quota automation
# This script runs after Terraform apply to validate quota requests were submitted successfully

set -euo pipefail

# Configuration
SERVICE_CODE="vpc"
QUOTA_CODE="L-0EA8095F"
REGION="us-east-1"  # Must be us-east-1 for global quotas
TARGET_QUOTA=200

# Colors for output (if terminal supports it)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a /tmp/aft-quota-validation.log
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a /tmp/aft-quota-validation.log
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a /tmp/aft-quota-validation.log
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a /tmp/aft-quota-validation.log
}

# Function to get account information
get_account_info() {
    local account_id=""
    local account_arn=""
    
    if aws sts get-caller-identity &>/dev/null; then
        account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "Unknown")
        account_arn=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || echo "Unknown")
    fi
    
    log_info "Account ID: $account_id"
    log_info "Account ARN: $account_arn"
    
    echo "$account_id"
}

# Function to validate quota request was submitted
validate_quota_request() {
    log_info "Validating Security Group quota request submission..."
    
    # Get current quota information
    local quota_info
    quota_info=$(aws service-quotas get-service-quota \
        --service-code "$SERVICE_CODE" \
        --quota-code "$QUOTA_CODE" \
        --region "$REGION" \
        --output json 2>/dev/null || echo "ERROR")
    
    if [[ "$quota_info" == "ERROR" ]]; then
        log_error "Failed to retrieve current quota information"
        return 1
    fi
    
    local current_value
    current_value=$(echo "$quota_info" | jq -r '.Quota.Value' 2>/dev/null || echo "0")
    
    log_info "Current quota value: $current_value"
    
    # Check for recent quota requests
    local requests
    requests=$(aws service-quotas list-requested-service-quota-change-history \
        --service-code "$SERVICE_CODE" \
        --region "$REGION" \
        --output json 2>/dev/null || echo "ERROR")
    
    if [[ "$requests" == "ERROR" ]]; then
        log_error "Failed to retrieve quota request history"
        return 1
    fi
    
    # Look for recent requests for our quota
    local recent_requests
    recent_requests=$(echo "$requests" | jq -r --arg quota_code "$QUOTA_CODE" --arg target "$TARGET_QUOTA" '
        .RequestedQuotas[] | 
        select(.QuotaCode == $quota_code and .DesiredValue == ($target | tonumber)) |
        select(.Created | fromdateiso8601 > (now - 3600)) |  # Within last hour
        "\(.Id)|\(.Status)|\(.DesiredValue)|\(.Created)"
    ' 2>/dev/null || echo "")
    
    if [[ -n "$recent_requests" ]]; then
        log_success "Found recent quota request(s):"
        echo "$recent_requests" | while IFS='|' read -r id status desired created; do
            if [[ -n "$id" ]]; then
                log_success "  Request ID: $id"
                log_success "  Status: $status"  
                log_success "  Desired Value: $desired"
                log_success "  Created: $created"
            fi
        done
        return 0
    else
        # Check if quota is already at target value
        if [[ "$current_value" == "$TARGET_QUOTA" ]] || [[ "$current_value" == "${TARGET_QUOTA}.0" ]]; then
            log_success "Quota is already at target value ($TARGET_QUOTA)"
            return 0
        else
            log_warning "No recent quota requests found and quota is not at target value"
            log_warning "Expected: $TARGET_QUOTA, Current: $current_value"
            return 1
        fi
    fi
}

# Function to validate Terraform state
validate_terraform_state() {
    log_info "Validating Terraform state for quota resources..."
    
    # Check if Terraform state file exists and contains our resources
    if [[ -f "terraform.tfstate" ]]; then
        # Check for quota resource in state
        if grep -q "aws_servicequotas_service_quota" terraform.tfstate 2>/dev/null; then
            log_success "Terraform state contains quota resource"
            
            # Extract resource details if possible
            local resource_id
            resource_id=$(jq -r '.resources[] | select(.type=="aws_servicequotas_service_quota") | .instances[0].attributes.id' terraform.tfstate 2>/dev/null || echo "Unknown")
            
            if [[ "$resource_id" != "Unknown" && "$resource_id" != "null" ]]; then
                log_success "Quota resource ID: $resource_id"
            fi
            
            return 0
        else
            log_warning "Terraform state does not contain expected quota resource"
            return 1
        fi
    else
        log_warning "Terraform state file not found"
        return 1
    fi
}

# Function to generate validation report
generate_report() {
    local account_id="$1"
    local validation_status="$2"
    
    log_info "Generating validation report..."
    
    cat > /tmp/aft-quota-validation-report.json << REPORT_EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "account_id": "$account_id",
    "service_code": "$SERVICE_CODE",
    "quota_code": "$QUOTA_CODE",
    "target_quota": $TARGET_QUOTA,
    "region": "$REGION",
    "validation_status": "$validation_status",
    "aft_automation": "security-group-quota",
    "version": "1.0"
}
REPORT_EOF
    
    log_success "Validation report saved to: /tmp/aft-quota-validation-report.json"
    
    # Also log the report content
    log_info "Validation Report:"
    cat /tmp/aft-quota-validation-report.json | jq '.' 2>/dev/null || cat /tmp/aft-quota-validation-report.json
}

# Function to handle errors and cleanup
handle_error() {
    local exit_code=$?
    log_error "Validation failed with exit code: $exit_code"
    
    # Don't fail the AFT pipeline - just log the issue
    log_warning "Continuing AFT pipeline despite validation warnings"
    
    # Generate error report
    generate_report "${account_id:-Unknown}" "FAILED"
    
    # Exit with success to avoid breaking AFT pipeline
    exit 0
}

# Main execution
main() {
    local account_id
    local validation_success=true
    
    # Set up error handling
    trap handle_error ERR
    
    log_info "Starting AFT post-API validation for Security Group quota automation"
    log_info "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    # Get account information
    account_id=$(get_account_info)
    
    # Validate prerequisites
    if ! command -v aws &>/dev/null; then
        log_error "AWS CLI not available"
        validation_success=false
    fi
    
    if ! command -v jq &>/dev/null; then
        log_warning "jq not available - some validations will be limited"
    fi
    
    # Validate quota request
    if ! validate_quota_request; then
        log_warning "Quota request validation failed"
        validation_success=false
    fi
    
    # Validate Terraform state
    if ! validate_terraform_state; then
        log_warning "Terraform state validation failed"
        validation_success=false
    fi
    
    # Generate final report
    if [[ "$validation_success" == true ]]; then
        log_success "All validations passed successfully"
        generate_report "$account_id" "SUCCESS"
    else
        log_warning "Some validations failed - check logs for details"
        generate_report "$account_id" "PARTIAL"
    fi
    
    log_info "AFT post-API validation completed"
    
    # Always exit successfully to avoid breaking AFT pipeline
    exit 0
}

# Check if jq is available (optional but helpful)
if ! command -v jq &>/dev/null; then
    echo "[WARNING] jq is not installed - some JSON parsing will be limited"
fi

# Run main function
main "$@"
