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
        region_key   = "region1"
        target_value = local.quota_config.quota_value
        resource_id  = aws_servicequotas_service_quota.security_group_rules_region1.id
      }
      (local.target_regions.region2) = {
        region_key   = "region2"
        target_value = local.quota_config.quota_value
        resource_id  = aws_servicequotas_service_quota.security_group_rules_region2.id
      }
      (local.target_regions.region3) = {
        region_key   = "region3"
        target_value = local.quota_config.quota_value
        resource_id  = aws_servicequotas_service_quota.security_group_rules_region3.id
      }
    }
    
    managed_regions = values(local.target_regions)
    total_regions   = length(local.target_regions)
  }
}

output "quota_values_by_region" {
  description = "Target quota values by region"
  value = {
    (local.target_regions.region1) = local.quota_config.quota_value
    (local.target_regions.region2) = local.quota_config.quota_value
    (local.target_regions.region3) = local.quota_config.quota_value
  }
}

output "quota_resource_ids" {
  description = "Service quota resource IDs for reference"
  value = {
    (local.target_regions.region1) = aws_servicequotas_service_quota.security_group_rules_region1.id
    (local.target_regions.region2) = aws_servicequotas_service_quota.security_group_rules_region2.id
    (local.target_regions.region3) = aws_servicequotas_service_quota.security_group_rules_region3.id
  }
}