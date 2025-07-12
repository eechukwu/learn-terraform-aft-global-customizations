locals {
  target_regions = [
    "us-east-1",
    "us-west-2",
    "eu-west-1"
  ]

  quota_config = {
    security_groups = {
      service_code = "vpc"
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
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {} 