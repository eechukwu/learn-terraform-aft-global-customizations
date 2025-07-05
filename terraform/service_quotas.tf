
# Service quota resources
resource "aws_servicequotas_service_quota" "security_group_rules" {
  for_each = local.target_regions

  provider     = aws[each.key]
  service_code = local.quota_config.service_code
  quota_code   = local.quota_config.quota_code
  value        = local.quota_config.quota_value
}

# Data sources to read current quota values
data "aws_servicequotas_service_quota" "current_quotas" {
  for_each = local.target_regions

  provider     = aws[each.key]
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
      for region_key, region_name in local.target_regions :
      region_name => {
        region_key    = region_key
        current_value = data.aws_servicequotas_service_quota.current_quotas[region_key].value
        target_value  = local.quota_config.quota_value
        resource_id   = aws_servicequotas_service_quota.security_group_rules[region_key].id
      }
    }
    
    managed_regions = values(local.target_regions)
    total_regions   = length(local.target_regions)
  }
}

output "quota_values_by_region" {
  description = "Current quota values by region (simplified output)"
  value = {
    for region_key, region_name in local.target_regions :
    region_name => data.aws_servicequotas_service_quota.current_quotas[region_key].value
  }
}
