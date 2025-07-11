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

output "sns_topic_arn" {
  description = "ARN of the SNS topic for quota notifications"
  value       = aws_sns_topic.quota_notifications.arn
}

output "sqs_dlq_arn" {
  description = "ARN of the Dead Letter Queue"
  value       = aws_sqs_queue.lambda_dlq.arn
}

output "target_regions" {
  description = "List of target regions being monitored"
  value       = local.target_regions
}

output "quota_config" {
  description = "Quota configurations being monitored"
  value       = local.quota_config
} 