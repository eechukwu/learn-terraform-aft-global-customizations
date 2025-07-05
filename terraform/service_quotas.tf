###############################################################################
# Service quota automation – zero repetition version
###############################################################################

terraform {
  required_version  = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

############################
# QUOTA REQUESTS
############################
resource "aws_servicequotas_service_quota" "sg_rules" {
  for_each    = { for r in local.target_regions_clean : r => r }
  provider    = aws.${replace(each.key, "-", "_")}

  service_code = var.quota_service_code   # "vpc"
  quota_code   = var.quota_code           # "L-0EA8095F"
  value        = var.default_target_quota_value

  # enable/disable all regions at once
  count = var.enable_quota_automation ? 1 : 0
}

############################
# DATA SOURCES FOR OUTPUTS
############################
data "aws_servicequotas_service_quota" "live" {
  for_each   = aws_servicequotas_service_quota.sg_rules
  provider   = aws.${replace(each.key, "-", "_")}

  service_code = var.quota_service_code
  quota_code   = var.quota_code
}

output "security_group_quota_values" {
  value = {
    for r, ds in data.aws_servicequotas_service_quota.live :
    r => ds.value
  }
}