############################
# SINGLE QUOTA RESOURCE
############################
resource "aws_servicequotas_service_quota" "sg_rules" {
  # Use explicit provider references instead of dynamic lookup
  for_each = {
    "us-east-1"      = aws.us_east_1
    "eu-west-2"      = aws.eu_west_2
    "ap-southeast-1" = aws.ap_southeast_1
    "us-west-2"      = aws.us_west_2
    "ca-central-1"   = aws.ca_central_1
  }

  provider     = each.value
  service_code = var.quota_service_code
  quota_code   = var.quota_code
  value        = var.default_target_quota_value
}

############################
# MATCHING DATA SOURCE
############################
data "aws_servicequotas_service_quota" "live" {
  for_each = {
    "us-east-1"      = aws.us_east_1
    "eu-west-2"      = aws.eu_west_2
    "ap-southeast-1" = aws.ap_southeast_1
    "us-west-2"      = aws.us_west_2
    "ca-central-1"   = aws.ca_central_1
  }

  provider     = each.value
  service_code = var.quota_service_code
  quota_code   = var.quota_code
}

############################
# OUTPUT
############################
output "security_group_quota_values" {
  value = {
    for r, _ in {
      "us-east-1"      = aws.us_east_1
      "eu-west-2"      = aws.eu_west_2
      "ap-southeast-1" = aws.ap_southeast_1
      "us-west-2"      = aws.us_west_2
      "ca-central-1"   = aws.ca_central_1
    } :
    r => data.aws_servicequotas_service_quota.live[r].value
  }
}
