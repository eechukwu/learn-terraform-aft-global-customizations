# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  # Account ID derived from data source
  account_id = data.aws_caller_identity.current.account_id
  
  # Target regions for quota monitoring
  target_regions = [
    "us-east-1",
    "us-west-2",
    "eu-west-1",
    "ap-southeast-1"
  ]
  
  # Multiple quota configurations
  quota_config = {
    security_groups = {
      service_code = "vpc"
      quota_code   = "L-0EA8095F"
      quota_value  = 200
      description  = "Security Groups per VPC"
    }
    
    elastic_ips = {
      service_code = "ec2"
      quota_code   = "L-0263D0A3"
      quota_value  = 20
      description  = "Elastic IP addresses per Region"
    }
  }
  
  # Lambda configuration
  lambda_config = {
    function_name = "aft-quota-manager-${local.account_id}"
    timeout      = 900
    memory_size  = 512
  }
  
  # Common tags for all resources
  common_tags = {
    Environment = "production"
    Project     = "aft-quota-manager"
    ManagedBy   = "terraform"
  }
}