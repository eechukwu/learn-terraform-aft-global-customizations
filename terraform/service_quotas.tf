############################
# SINGLE QUOTA RESOURCE
############################
resource "aws_servicequotas_service_quota" "sg_rules_us_east_1" {
  provider     = aws.us_east_1
  service_code = var.quota_service_code
  quota_code   = var.quota_code
  value        = var.default_target_quota_value
}

resource "aws_servicequotas_service_quota" "sg_rules_eu_west_2" {
  provider     = aws.eu_west_2
  service_code = var.quota_service_code
  quota_code   = var.quota_code
  value        = var.default_target_quota_value
}

resource "aws_servicequotas_service_quota" "sg_rules_ap_southeast_1" {
  provider     = aws.ap_southeast_1
  service_code = var.quota_service_code
  quota_code   = var.quota_code
  value        = var.default_target_quota_value
}

resource "aws_servicequotas_service_quota" "sg_rules_us_west_2" {
  provider     = aws.us_west_2
  service_code = var.quota_service_code
  quota_code   = var.quota_code
  value        = var.default_target_quota_value
}

resource "aws_servicequotas_service_quota" "sg_rules_ca_central_1" {
  provider     = aws.ca_central_1
  service_code = var.quota_service_code
  quota_code   = var.quota_code
  value        = var.default_target_quota_value
}

############################
# MATCHING DATA SOURCE
############################
data "aws_servicequotas_service_quota" "live_us_east_1" {
  provider     = aws.us_east_1
  service_code = var.quota_service_code
  quota_code   = var.quota_code
}

data "aws_servicequotas_service_quota" "live_eu_west_2" {
  provider     = aws.eu_west_2
  service_code = var.quota_service_code
  quota_code   = var.quota_code
}

data "aws_servicequotas_service_quota" "live_ap_southeast_1" {
  provider     = aws.ap_southeast_1
  service_code = var.quota_service_code
  quota_code   = var.quota_code
}

data "aws_servicequotas_service_quota" "live_us_west_2" {
  provider     = aws.us_west_2
  service_code = var.quota_service_code
  quota_code   = var.quota_code
}

data "aws_servicequotas_service_quota" "live_ca_central_1" {
  provider     = aws.ca_central_1
  service_code = var.quota_service_code
  quota_code   = var.quota_code
}

############################
# OUTPUT
############################
output "security_group_quota_values" {
  value = {
    "us-east-1"      = data.aws_servicequotas_service_quota.live_us_east_1.value
    "eu-west-2"      = data.aws_servicequotas_service_quota.live_eu_west_2.value
    "ap-southeast-1" = data.aws_servicequotas_service_quota.live_ap_southeast_1.value
    "us-west-2"      = data.aws_servicequotas_service_quota.live_us_west_2.value
    "ca-central-1"   = data.aws_servicequotas_service_quota.live_ca_central_1.value
  }
}