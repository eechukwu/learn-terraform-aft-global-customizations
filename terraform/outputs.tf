# Lambda function outputs
output "lambda_function_name" {
  description = "Name of the quota manager Lambda function"
  value       = module.quota_manager.function_name
}

output "lambda_function_arn" {
  description = "ARN of the quota manager Lambda function"
  value       = module.quota_manager.function_arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = module.quota_manager.role_arn
}

# SNS and SQS outputs
output "sns_topic_arn" {
  description = "ARN of the SNS topic for quota notifications"
  value       = aws_sns_topic.quota_notifications.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for quota notifications"
  value       = aws_sns_topic.quota_notifications.name
}

output "sqs_dlq_arn" {
  description = "ARN of the Dead Letter Queue"
  value       = aws_sqs_queue.lambda_dlq.arn
}

output "sqs_dlq_name" {
  description = "Name of the Dead Letter Queue"
  value       = aws_sqs_queue.lambda_dlq.name
}

# KMS and logging outputs
output "kms_key_id" {
  description = "ID of the KMS key used for encryption"
  value       = aws_kms_key.lambda_logs.id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = aws_kms_key.lambda_logs.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.quota_lambda_logs.name
}

# Configuration outputs
output "target_regions" {
  description = "List of target regions being monitored"
  value       = local.target_regions
}

output "quota_config" {
  description = "Quota configurations being monitored"
  value       = local.quota_config
  sensitive   = false
}

# Monitoring outputs
output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for quota monitoring"
  value       = aws_cloudwatch_event_rule.quota_monitor.name
}

output "lambda_alias_name" {
  description = "Name of the Lambda alias"
  value       = aws_lambda_alias.live.name
}

output "lambda_alias_arn" {
  description = "ARN of the Lambda alias"
  value       = aws_lambda_alias.live.arn
}

# Slack integration output (conditional)
output "slack_lambda_function_name" {
  description = "Name of the Slack notification Lambda function (if enabled)"
  value       = try(module.sns_to_slack.lambda_function_name, null)
}