# Essential outputs only
output "lambda_function_name" {
  description = "Name of the quota manager Lambda function"
  value       = module.quota_manager.function_name
}

output "lambda_function_arn" {
  description = "ARN of the quota manager Lambda function"
  value       = module.quota_manager.function_arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = aws_sns_topic.quota_notifications.arn
}

output "target_regions" {
  description = "Regions being monitored"
  value       = local.target_regions
}