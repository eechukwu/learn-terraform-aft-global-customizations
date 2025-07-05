
# Service quota resources - Region 1
resource "aws_servicequotas_service_quota" "security_group_rules_region1" {
  provider     = aws.region1
  service_code = local.quota_config.service_code
  quota_code   = local.quota_config.quota_code
  value        = local.quota_config.quota_value
}

# Service quota resources - Region 2
resource "aws_servicequotas_service_quota" "security_group_rules_region2" {
  provider     = aws.region2
  service_code = local.quota_config.service_code
  quota_code   = local.quota_config.quota_code
  value        = local.quota_config.quota_value
}

# Service quota resources - Region 3
resource "aws_servicequotas_service_quota" "security_group_rules_region3" {
  provider     = aws.region3
  service_code = local.quota_config.service_code
  quota_code   = local.quota_config.quota_code
  value        = local.quota_config.quota_value
}

# Data sources to read current quota values - Region 1
data "aws_servicequotas_service_quota" "current_quotas_region1" {
  provider     = aws.region1
  service_code = local.quota_config.service_code
  quota_code   = local.quota_config.quota_code
}

# Data sources to read current quota values - Region 2
data "aws_servicequotas_service_quota" "current_quotas_region2" {
  provider     = aws.region2
  service_code = local.quota_config.service_code
  quota_code   = local.quota_config.quota_code
}

# Data sources to read current quota values - Region 3
data "aws_servicequotas_service_quota" "current_quotas_region3" {
  provider     = aws.region3
  service_code = local.quota_config.service_code
  quota_code   = local.quota_config.quota_code
}

# ==========================================
# outputs.tf - Output values
# ==========================================
output "quota_management_summary" {
  description = "Summary of security group quota management across regions"
  value = {
    quota_details = {
      service_code = local.quota_config.service_code
      quota_code   = local.quota_config.quota_code
      description  = "Rules per security group"
      target_value = local.quota_config.quota_value
    }
    
    regional_quotas = {
      (local.target_regions.region1) = {
        region_key    = "region1"
        current_value = data.aws_servicequotas_service_quota.current_quotas_region1.value
        target_value  = local.quota_config.quota_value
        resource_id   = aws_servicequotas_service_quota.security_group_rules_region1.id
      }
      (local.target_regions.region2) = {
        region_key    = "region2"
        current_value = data.aws_servicequotas_service_quota.current_quotas_region2.value
        target_value  = local.quota_config.quota_value
        resource_id   = aws_servicequotas_service_quota.security_group_rules_region2.id
      }
      (local.target_regions.region3) = {
        region_key    = "region3"
        current_value = data.aws_servicequotas_service_quota.current_quotas_region3.value
        target_value  = local.quota_config.quota_value
        resource_id   = aws_servicequotas_service_quota.security_group_rules_region3.id
      }
    }
    
    managed_regions = values(local.target_regions)
    total_regions   = length(local.target_regions)
  }
}

output "quota_values_by_region" {
  description = "Current quota values by region (simplified output)"
  value = {
    (local.target_regions.region1) = data.aws_servicequotas_service_quota.current_quotas_region1.value
    (local.target_regions.region2) = data.aws_servicequotas_service_quota.current_quotas_region2.value
    (local.target_regions.region3) = data.aws_servicequotas_service_quota.current_quotas_region3.value
  }
}

