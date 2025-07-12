output "lambda_function_name" {
  description = "Name of the quota manager Lambda function"
  value       = module.lambda.function_name
}

output "lambda_function_arn" {
  description = "ARN of the quota manager Lambda function"
  value       = module.lambda.function_arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = module.lambda.role_arn
}

# TODO: MONDAY - Update to use company SNS module ARN
output "sns_topic_arn" {
  description = "ARN of the SNS topic for quota notifications"
  value       = aws_sns_topic.notifications.arn
}

output "sqs_dlq_arn" {
  description = "ARN of the Dead Letter Queue"
  value       = aws_sqs_queue.dlq.arn
}

output "target_regions" {
  description = "List of target regions being monitored"
  value       = local.target_regions
}

output "quota_config" {
  description = "Quota configurations being monitored"
  value       = local.quota_config
} 