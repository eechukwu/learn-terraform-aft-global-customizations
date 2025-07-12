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
    "eu-west-1"
  ]
  
  # Multiple quota configurations
  quota_config = {
    security_groups = {
      service_code = "ec2"
      quota_code   = "L-0EA8095F"
      quota_value  = 200
      description  = "Security Groups per VPC"
    }
    
    iam_roles = {
      service_code = "iam"
      quota_code   = "L-FE177D2D"
      quota_value  = 5000
      description  = "IAM Roles per account"
    }
    
    iam_policies = {
      service_code = "iam"
      quota_code   = "L-0B55BAF2"
      quota_value  = 1500
      description  = "IAM Customer managed policies per account"
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