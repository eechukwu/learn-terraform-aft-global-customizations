# ==========================================
# service_quotas.tf - Quota management resources
# ==========================================

# Service quota resources
resource "aws_servicequotas_service_quota" "security_group_rules_region1" {
  provider     = aws.region1
  service_code = local.quota_config.service_code
  quota_code   = local.quota_config.quota_code
  value        = local.quota_config.quota_value
}

resource "aws_servicequotas_service_quota" "security_group_rules_region2" {
  provider     = aws.region2
  service_code = local.quota_config.service_code
  quota_code   = local.quota_config.quota_code
  value        = local.quota_config.quota_value
}

resource "aws_servicequotas_service_quota" "security_group_rules_region3" {
  provider     = aws.region3
  service_code = local.quota_config.service_code
  quota_code   = local.quota_config.quota_code
  value        = local.quota_config.quota_value
}