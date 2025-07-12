resource "random_id" "lambda_suffix" {
  byte_length = 4
}

resource "aws_sqs_queue" "lambda_dlq" {
  name = "aft-quota-lambda-dlq-${data.aws_caller_identity.current.account_id}-${random_id.lambda_suffix.hex}"
  tags = local.common_tags
}

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
        Resource = "*"
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
        Resource = "*"
      },
      {
        Sid    = "Allow SNS service"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_kms_alias" "lambda_logs" {
  name          = "alias/aft-quota-manager-logs-${data.aws_caller_identity.current.account_id}-${random_id.lambda_suffix.hex}"
  target_key_id = aws_kms_key.lambda_logs.key_id
}

resource "aws_sns_topic" "quota_notifications" {
  name              = "aft-quota-notifications-${data.aws_caller_identity.current.account_id}-${random_id.lambda_suffix.hex}"
  kms_master_key_id = aws_kms_key.lambda_logs.arn
  tags              = local.common_tags
}

module "sns_to_slack" {
  source  = "terraform-aws-modules/notify-slack/aws"
  version = "~> 6.0"

  sns_topic_name    = aws_sns_topic.quota_notifications.name
  slack_webhook_url = var.slack_webhook_url
  slack_channel     = var.slack_channel_name
  slack_username    = "AWS-Quota-Manager"

  tags = local.common_tags
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

  tags = local.common_tags

  attach_policy = true
  manage_log_group = true
  log_group_retention_days = 365
  encrypted_log_group = true
  kms_key_id = aws_kms_key.lambda_logs.arn
  
  reserved_concurrent_executions = "5"
  
  attach_dead_letter_config = true
  dead_letter_config = {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }
  
  permissions_boundary = ""

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
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.lambda_dlq.arn
      }
    ]
  })

  environment = {
    variables = {
      TARGET_REGIONS = join(",", local.target_regions)
      SNS_TOPIC_ARN = aws_sns_topic.quota_notifications.arn
      QUOTA_CONFIG = jsonencode(local.quota_config)
      LOG_LEVEL = "INFO"
    }
  }

  depends_on = [
    aws_sqs_queue.lambda_dlq
  ]
}

resource "aws_lambda_alias" "live" {
  name             = "live"
  description      = "Live production alias"
  function_name    = module.quota_manager.function_name
  function_version = "$LATEST"
}

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