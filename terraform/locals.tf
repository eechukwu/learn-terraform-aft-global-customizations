locals {
  # Target regions for quota management
  target_regions = {
    primary   = "us-east-1"
    secondary = "eu-west-2"
    tertiary  = "ap-southeast-1"
  }
  
  # Service quota configuration
  quota_config = {
    service_code = "vpc"
    quota_code   = "L-0EA8095F"  # Rules per security group
    quota_value  = 200
  }
  
  # Common tags for all resources
  common_tags = {
    ManagedBy   = "AFT"
    Environment = "global"
    Purpose     = "quota-management"
  }
}