terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

# SNS Topic for quota notifications
resource "aws_sns_topic" "quota_notifications" {
  name = "aft-quota-notifications-${data.aws_caller_identity.current.account_id}"
  
  tags = var.tags
}

# Lambda module with minimal configuration
module "quota_manager" {
  source = "github.com/eechukwu/tf-aws-lambda-develop"

  function_name = "aft-quota-manager-${data.aws_caller_identity.current.account_id}"
  description   = "AFT Quota Manager"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = "300"
  memory_size   = "256"
  source_path   = "${path.module}"

  tags = var.tags

  # Disable all IAM and log group management
  attach_policy = false
  manage_log_group = false
  
  reserved_concurrent_executions = "5"

  environment = {
    variables = merge({
      TARGET_REGIONS = join(",", local.target_regions)
      SNS_TOPIC_ARN = aws_sns_topic.quota_notifications.arn
    }, 
    merge([
      for quota_name, quota_config in local.quota_config : {
        for key, value in quota_config : 
        "QUOTA_CONFIG_${upper(replace(quota_name, "-", "_"))}_${upper(key)}" => tostring(value)
      }
    ]...)
    )
  }
}

# SNS to Slack module
module "sns_to_slack" {
  source = "github.com/eechukwu/tf-aws-sns-slack-develop"

  function_name = "aft-quota-slack-notifications-${data.aws_caller_identity.current.account_id}"
  
  slack_token_ssm_parameter_name = var.slack_token_ssm_parameter_name
  sns_topic_arn                 = aws_sns_topic.quota_notifications.arn
  default_channel_name          = var.slack_channel_name
  lambda_log_level              = "INFO"
  
  additional_tags = var.tags
} 