data "aws_region" "current" {}

resource "random_id" "lambda_suffix" {
  byte_length = 4
}

resource "aws_kms_key" "lambda_logs" {
  description             = "KMS key for Lambda quota manager logs"
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM root permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "logs.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnEquals = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${local.account_id}:log-group:/aws/lambda/${local.lambda_config.function_name}"
          }
        }
      },
      {
        Sid    = "Allow Lambda service"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.quota_lambda_role.arn
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_kms_alias" "lambda_logs" {
  name          = "alias/aft-quota-manager-logs-${local.account_id}-${random_id.lambda_suffix.hex}"
  target_key_id = aws_kms_key.lambda_logs.key_id
}

resource "aws_cloudwatch_log_group" "quota_lambda_logs" {
  name              = "/aws/lambda/${local.lambda_config.function_name}"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.lambda_logs.arn
  tags              = local.common_tags
}

data "archive_file" "quota_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/quota_manager.zip"
  
  source {
    content = file("${path.module}/lambda_function.py")
    filename = "index.py"
  }
}

resource "aws_iam_role" "quota_lambda_role" {
  name = "aft-quota-lambda-role-${local.account_id}-${random_id.lambda_suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "quota_lambda_policy" {
  name = "quota-management-policy"
  role = aws_iam_role.quota_lambda_role.id

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
        Condition = {
          StringEquals = {
            "servicequotas:service-code" = local.quota_config.service_code
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.quota_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_sns_policy" {
  name = "lambda-sns-policy"
  role = aws_iam_role.quota_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.quota_notifications.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "service_linked_role_policy" {
  name = "service-linked-role-policy"
  role = aws_iam_role.quota_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
}

resource "aws_lambda_function" "quota_manager" {
  filename         = data.archive_file.quota_lambda_zip.output_path
  function_name    = local.lambda_config.function_name
  role            = aws_iam_role.quota_lambda_role.arn
  handler         = "index.lambda_handler"
  source_code_hash = data.archive_file.quota_lambda_zip.output_base64sha256
  runtime         = "python3.12"
  timeout         = local.lambda_config.timeout
  memory_size     = local.lambda_config.memory_size
  publish         = true

  environment {
    variables = {
      SERVICE_CODE = local.quota_config.service_code
      QUOTA_CODE   = local.quota_config.quota_code
      QUOTA_VALUE  = local.quota_config.quota_value
      LOG_LEVEL    = "INFO"
      SNS_TOPIC_ARN = aws_sns_topic.quota_notifications.arn
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_cloudwatch_log_group.quota_lambda_logs,
  ]
}

resource "aws_lambda_alias" "live" {
  name             = "live"
  description      = "Live production alias"
  function_name    = aws_lambda_function.quota_manager.function_name
  function_version = aws_lambda_function.quota_manager.version
}

resource "aws_sns_topic" "quota_notifications" {
  name              = "aft-quota-notifications-${local.account_id}-${random_id.lambda_suffix.hex}"
  kms_master_key_id = aws_kms_key.lambda_logs.arn
  tags              = local.common_tags
}

resource "aws_sns_topic_subscription" "quota_email_notifications" {
  topic_arn = aws_sns_topic.quota_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_cloudwatch_event_rule" "quota_monitor" {
  name                = "aft-quota-monitor-${local.account_id}-${random_id.lambda_suffix.hex}"
  description         = "Monitor quota request approvals every 10 minutes"
  schedule_expression = "rate(10 minutes)"
  tags                = local.common_tags
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.quota_monitor.name
  target_id = "QuotaMonitorTarget-${local.account_id}-${random_id.lambda_suffix.hex}"
  arn       = aws_lambda_alias.live.arn
  
  input = jsonencode({
    action = "monitor_requests"
    regions = local.target_regions
  })
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.quota_manager.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.quota_monitor.arn
  qualifier     = aws_lambda_alias.live.name
}

resource "aws_lambda_invocation" "quota_request" {
  function_name = aws_lambda_alias.live.function_name
  qualifier     = aws_lambda_alias.live.name
  
  input = jsonencode({
    action = "request_quotas"
    regions = local.target_regions
    quota_value = local.quota_config.quota_value
  })

  depends_on = [
    aws_lambda_function.quota_manager,
    aws_iam_role_policy.quota_lambda_policy,
    aws_iam_role_policy.service_linked_role_policy,
    aws_iam_role_policy.lambda_sns_policy,
    aws_lambda_alias.live
  ]
  
  triggers = {
    lambda_code_hash = data.archive_file.quota_lambda_zip.output_base64sha256
    permissions_hash = md5(jsonencode([
      aws_iam_role_policy.quota_lambda_policy.policy,
      aws_iam_role_policy.service_linked_role_policy.policy
    ]))
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "aft-quota-manager-errors-${local.account_id}-${random_id.lambda_suffix.hex}"
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
    FunctionName = aws_lambda_function.quota_manager.function_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "aft-quota-manager-duration-${local.account_id}-${random_id.lambda_suffix.hex}"
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
    FunctionName = aws_lambda_function.quota_manager.function_name
  }

  tags = local.common_tags
}