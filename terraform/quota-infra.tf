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

# Random suffix for unique resource names
resource "random_id" "lambda_suffix" {
  byte_length = 4
}

# SQS Dead Letter Queue for Lambda error handling
resource "aws_sqs_queue" "lambda_dlq" {
  name = "aft-quota-lambda-dlq-${data.aws_caller_identity.current.account_id}-${random_id.lambda_suffix.hex}"
  tags = local.common_tags
}

# KMS Key for Lambda logs encryption
resource "aws_kms_key" "lambda_logs" {
  description             = "KMS key for Lambda quota manager logs"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM root permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "arn:aws:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:key/*"
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "arn:aws:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:key/*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/aft-quota-manager-${data.aws_caller_identity.current.account_id}*"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_kms_alias" "lambda_logs" {
  name          = "alias/aft-quota-manager-logs-${data.aws_caller_identity.current.account_id}-${random_id.lambda_suffix.hex}"
  target_key_id = aws_kms_key.lambda_logs.key_id
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "quota_lambda_logs" {
  name              = "/aws/lambda/aft-quota-manager-${data.aws_caller_identity.current.account_id}"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.lambda_logs.arn
  tags              = local.common_tags
}

# SNS Topic for notifications
resource "aws_sns_topic" "quota_notifications" {
  name              = "aft-quota-notifications-${data.aws_caller_identity.current.account_id}-${random_id.lambda_suffix.hex}"
  kms_master_key_id = aws_kms_key.lambda_logs.arn
  tags              = local.common_tags
}

# SNS to Slack module
module "sns_to_slack" {
  source = "github.com/eechukwu/tf-aws-sns-slack-develop"

  function_name = "aft-quota-slack-notifications-${data.aws_caller_identity.current.account_id}"
  
  slack_token_ssm_parameter_name = var.slack_token_ssm_parameter_name
  sns_topic_arn                 = aws_sns_topic.quota_notifications.arn
  default_channel_name          = var.slack_channel_name
  lambda_log_level              = "INFO"
  
  additional_tags = local.common_tags
}

# Lambda module with full configuration
module "quota_manager" {
  source = "github.com/eechukwu/tf-aws-lambda-develop"

  function_name = "aft-quota-manager-${data.aws_caller_identity.current.account_id}"
  description   = "AFT Quota Manager"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = "300"
  memory_size   = "256"
  source_path   = "${path.module}"

  tags = local.common_tags

  # Enable IAM and log group management
  attach_policy = true
  manage_log_group = false
  
  reserved_concurrent_executions = "5"
  
  # Dead Letter Queue configuration
  attach_dead_letter_config = true
  dead_letter_config = {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  # Service Quotas policy
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "servicequotas:GetServiceQuota",
          "servicequotas:RequestServiceQuotaIncrease",
          "servicequotas:ListRequestedServiceQuotaChangeHistory",
          "servicequotas:GetRequestedServiceQuotaChange",
          "servicequotas:ListServiceQuotas",
          "servicequotas:GetAWSDefaultServiceQuota"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.quota_notifications.arn
      },
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole"
        ]
        Resource = [
          "arn:aws:iam::*:role/aws-service-role/servicequotas.amazonaws.com/*"
        ]
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "servicequotas.amazonaws.com"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "iam:AttachRolePolicy",
          "iam:PutRolePolicy"
        ]
        Resource = [
          "arn:aws:iam::*:role/aws-service-role/servicequotas.amazonaws.com/*"
        ]
      }
    ]
  })

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

# Lambda alias for versioning
resource "aws_lambda_alias" "live" {
  name             = "live"
  description      = "Live production alias"
  function_name    = module.quota_manager.function_name
  function_version = "$LATEST"
}

# EventBridge rule for periodic monitoring
resource "aws_cloudwatch_event_rule" "quota_monitor" {
  name                = "aft-quota-monitor-${data.aws_caller_identity.current.account_id}-${random_id.lambda_suffix.hex}"
  description         = "Monitor quota request approvals every 10 minutes"
  schedule_expression = "rate(10 minutes)"
  tags                = local.common_tags
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.quota_monitor.name
  target_id = "QuotaMonitorTarget-${data.aws_caller_identity.current.account_id}-${random_id.lambda_suffix.hex}"
  arn       = aws_lambda_alias.live.arn
  
  input = jsonencode({
    action = "monitor_requests"
    regions = local.target_regions
  })
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = module.quota_manager.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.quota_monitor.arn
  qualifier     = aws_lambda_alias.live.name
}

# CloudWatch alarms for monitoring
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "aft-quota-manager-errors-${data.aws_caller_identity.current.account_id}-${random_id.lambda_suffix.hex}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Lambda error monitoring"
  alarm_actions       = [aws_sns_topic.quota_notifications.arn]
  ok_actions          = [aws_sns_topic.quota_notifications.arn]

  dimensions = {
    FunctionName = module.quota_manager.function_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "aft-quota-manager-duration-${data.aws_caller_identity.current.account_id}-${random_id.lambda_suffix.hex}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = "600000"
  alarm_description   = "Lambda duration monitoring"
  alarm_actions       = [aws_sns_topic.quota_notifications.arn]
  ok_actions          = [aws_sns_topic.quota_notifications.arn]

  dimensions = {
    FunctionName = module.quota_manager.function_name
  }

  tags = local.common_tags
} 