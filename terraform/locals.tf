# Configuration constants for AFT quota management
locals {
  target_regions = [
    "us-east-1",
    "us-west-2",
    "eu-west-1", 
    "eu-west-2",
    "ap-southeast-1"
  ]
  
  quota_config = {
    service_code = "vpc"
    quota_code   = "L-0EA8095F"
    quota_value  = 200
  }
  
  lambda_config = {
    function_name = "aft-quota-manager-${random_id.lambda_suffix.hex}"
    timeout      = 900
    memory_size  = 512
  }
  
  account_id = data.aws_caller_identity.current.account_id
  
  common_tags = {
    ManagedBy = "AFT"
    Purpose   = "quota-management"
  }
}

resource "random_id" "lambda_suffix" {
  byte_length = 4
}

data "aws_caller_identity" "current" {}