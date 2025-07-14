resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_sqs_queue" "dlq" {
  name              = "aft-quota-lambda-dlq-${data.aws_caller_identity.current.account_id}-${random_id.suffix.hex}"
  kms_master_key_id = aws_kms_key.logs.arn
  tags              = merge(local.common_tags, {
    "williamhill:role" = "quota-manager-dlq"
    "williamhill:type" = "wh-infra"
  })
}

resource "aws_kms_key" "logs" {
  description             = "KMS key for Lambda logs"
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

  tags = merge(local.common_tags, {
    "williamhill:role" = "quota-manager-kms"
    "williamhill:type" = "wh-infra"
  })
}

resource "aws_kms_alias" "logs" {
  name          = "alias/aft-quota-manager-logs-${data.aws_caller_identity.current.account_id}-${random_id.suffix.hex}"
  target_key_id = aws_kms_key.logs.key_id
}

module "quota_notifications" {
  source = "git::https://gitlab.com/williamhillplc/technical-services/public-cloud/terraform-modules/tf-aws-notifications.git?ref=5.2.0"
  name = "aft-quota-manager-${data.aws_caller_identity.current.account_id}-notifications"
  additional_tags = merge(local.common_tags, {
    "williamhill:role" = "quota-manager"
    "williamhill:type" = "wh-infra"
  })
}

module "quota_notifications_to_slack" {
  source = "git::https://gitlab.com/williamhillplc/technical-services/public-cloud/terraform-modules/tf-aws-sns-slack-consumer.git?ref=6.0.0"
  source_sns_topic_arn    = module.quota_notifications.sns_topic_arn
  target_sns_topic_arn    = var.cloud_services_slack_topic_arn
  target_sns_topic_region = var.slack_notification_region
  slack_channel           = var.slack_channel_name
  additional_tags = merge(local.common_tags, {
    "williamhill:role" = "quota-manager-slack"
    "williamhill:type" = "wh-infra"
  })
}

module "lambda" {
  source = "git::https://gitlab.com/williamhillplc/technical-services/public-cloud/terraform-modules/tf-aws-lambda?ref=9.3.0"

  function_name = "aft-quota-manager-${data.aws_caller_identity.current.account_id}"
  description   = "Manages AWS service quotas automatically across multiple regions."
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = "300"
  memory_size   = "256"
  source_path   = "${path.module}"

  tags = merge(local.common_tags, {
    "williamhill:role" = "quota-manager-lambda"
    "williamhill:type" = "wh-infra"
  })

  attach_policy = true
  enabled       = true
  manage_log_group = true
  log_group_retention_days = 365
  encrypted_log_group = true
  kms_key_id = aws_kms_key.logs.arn
  
  attach_dead_letter_config = true
  dead_letter_config = {
    target_arn = aws_sqs_queue.dlq.arn
  }

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
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "servicequotas.amazonaws.com"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = module.quota_notifications.sns_topic_arn
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.dlq.arn
      }
    ]
  })

  environment = {
    variables = {
      TARGET_REGIONS = join(",", local.target_regions)
      SNS_TOPIC_ARN = module.quota_notifications.sns_topic_arn
      QUOTA_CONFIG = jsonencode(local.quota_config)
      LOG_LEVEL = "INFO"
    }
  }
}

resource "aws_lambda_alias" "live" {
  name             = "live"
  description      = "Live production alias"
  function_name    = module.lambda.function_name
  function_version = "$LATEST"
}

resource "aws_cloudwatch_event_rule" "monitor" {
  name                = "aft-quota-monitor-${data.aws_caller_identity.current.account_id}-${random_id.suffix.hex}"
  description         = "Monitor quota request approvals every 10 minutes"
  schedule_expression = "rate(10 minutes)"
  tags                = merge(local.common_tags, {
    "williamhill:role" = "quota-manager-scheduler"
    "williamhill:type" = "wh-infra"
  })
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.monitor.name
  target_id = "QuotaMonitorTarget-${data.aws_caller_identity.current.account_id}-${random_id.suffix.hex}"
  arn       = aws_lambda_alias.live.arn
  
  input = jsonencode({
    action = "monitor_requests"
    regions = local.target_regions
  })
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.monitor.arn
  qualifier     = aws_lambda_alias.live.name
}