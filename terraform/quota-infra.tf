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

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_sns_topic" "quota_notifications" {
  name = "aft-quota-notifications-${data.aws_caller_identity.current.account_id}"
}

resource "aws_sqs_queue" "lambda_dlq" {
  name = "aft-quota-lambda-dlq-${data.aws_caller_identity.current.account_id}"
  tags = var.tags
}

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

  attach_policy = true
  policy        = data.aws_iam_policy_document.quota_manager.json

  attach_dead_letter_config = true
  dead_letter_config = {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }
  
  reserved_concurrent_executions = "5"
  
  manage_log_group         = true
  log_group_retention_days = 365
  encrypted_log_group      = true

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

data "aws_iam_policy_document" "quota_manager" {
  statement {
    sid = "ServiceQuotasPermissions"
    effect = "Allow"
    actions = [
      "servicequotas:GetServiceQuota",
      "servicequotas:RequestServiceQuotaIncrease",
      "servicequotas:ListRequestedServiceQuotaChangeHistory",
      "servicequotas:GetRequestedServiceQuotaChange"
    ]
    resources = ["*"]
  }

  statement {
    sid = "SNSPublish"
    effect = "Allow"
    actions = [
      "sns:Publish"
    ]
    resources = [aws_sns_topic.quota_notifications.arn]
  }

  statement {
    sid = "ServiceLinkedRole"
    effect = "Allow"
    actions = [
      "iam:CreateServiceLinkedRole"
    ]
    resources = [
      "arn:aws:iam::*:role/aws-service-role/servicequotas.amazonaws.com/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["servicequotas.amazonaws.com"]
    }
  }
}

module "sns_to_slack" {
  source = "github.com/eechukwu/tf-aws-sns-slack-develop"

  function_name = "aft-quota-slack-notifications-${data.aws_caller_identity.current.account_id}"
  
  slack_token_ssm_parameter_name = var.slack_token_ssm_parameter_name
  sns_topic_arn                 = aws_sns_topic.quota_notifications.arn
  default_channel_name          = var.slack_channel_name
  lambda_log_level              = "INFO"
  
  additional_tags = var.tags
}

resource "aws_cloudwatch_event_rule" "quota_monitor" {
  name                = "aft-quota-monitor-${data.aws_caller_identity.current.account_id}"
  description         = "Monitor quota request approvals every 10 minutes"
  schedule_expression = "rate(10 minutes)"
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.quota_monitor.name
  target_id = "QuotaMonitorTarget"
  arn       = module.quota_manager.function_arn
  
  input = jsonencode({
    action      = "monitor_requests"
    regions     = local.target_regions
  })
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = module.quota_manager.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.quota_monitor.arn
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "aft-quota-manager-errors-${data.aws_caller_identity.current.account_id}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Lambda error monitoring"
  alarm_actions       = [aws_sns_topic.quota_notifications.arn]

  dimensions = {
    FunctionName = module.quota_manager.function_name
  }
} 