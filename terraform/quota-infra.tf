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

# Simple SNS to Slack Lambda function
resource "aws_lambda_function" "sns_to_slack" {
  filename         = data.archive_file.slack_lambda.output_path
  function_name    = "aft-quota-slack-notifications-${data.aws_caller_identity.current.account_id}"
  role            = aws_iam_role.slack_lambda_role.arn
  handler         = "index.handler"
  runtime         = "nodejs18.x"
  timeout         = 30
  memory_size     = 128

  environment {
    variables = {
      SLACK_TOKEN_SSM_PARAMETER_NAME = var.slack_token_ssm_parameter_name
      SNS_TOPIC_ARN                 = aws_sns_topic.quota_notifications.arn
      DEFAULT_CHANNEL_NAME          = var.slack_channel_name
      LOG_LEVEL                     = "INFO"
    }
  }

  tags = var.tags
}

data "archive_file" "slack_lambda" {
  type        = "zip"
  output_path = "${path.module}/slack-lambda.zip"
  source {
    content = <<EOF
const AWS = require('aws-sdk');
const https = require('https');

exports.handler = async (event) => {
    console.log('SNS to Slack Lambda triggered');
    
    const ssm = new AWS.SSM();
    const sns = new AWS.SNS();
    
    try {
        // Get Slack token from SSM
        const tokenParam = await ssm.getParameter({
            Name: process.env.SLACK_TOKEN_SSM_PARAMETER_NAME,
            WithDecryption: true
        }).promise();
        
        const slackToken = tokenParam.Parameter.Value;
        
        // Process SNS messages
        for (const record of event.Records) {
            const snsMessage = JSON.parse(record.Sns.Message);
            const channel = process.env.DEFAULT_CHANNEL_NAME;
            
            const slackMessage = {
                channel: channel,
                text: "Quota Update: " + (snsMessage.message || JSON.stringify(snsMessage))
            };
            
            // Send to Slack
            await sendToSlack(slackToken, slackMessage);
        }
        
        return { statusCode: 200, body: 'Success' };
    } catch (error) {
        console.error('Error:', error);
        throw error;
    }
};

async function sendToSlack(token, message) {
    return new Promise((resolve, reject) => {
        const data = JSON.stringify(message);
        const options = {
            hostname: 'slack.com',
            port: 443,
            path: '/api/chat.postMessage',
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${token}`,
                'Content-Length': data.length
            }
        };
        
        const req = https.request(options, (res) => {
            let body = '';
            res.on('data', (chunk) => body += chunk);
            res.on('end', () => resolve(body));
        });
        
        req.on('error', reject);
        req.write(data);
        req.end();
    });
}
EOF
    filename = "index.js"
  }
}

resource "aws_iam_role" "slack_lambda_role" {
  name = "aft-slack-lambda-role-${data.aws_caller_identity.current.account_id}"
  
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
}

resource "aws_iam_role_policy" "slack_lambda_policy" {
  name = "aft-slack-lambda-policy-${data.aws_caller_identity.current.account_id}"
  role = aws_iam_role.slack_lambda_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:*:*:parameter${var.slack_token_ssm_parameter_name}"
      }
    ]
  })
}

resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sns_to_slack.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.quota_notifications.arn
}

resource "aws_sns_topic_subscription" "slack_lambda_target" {
  topic_arn = aws_sns_topic.quota_notifications.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.sns_to_slack.arn
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