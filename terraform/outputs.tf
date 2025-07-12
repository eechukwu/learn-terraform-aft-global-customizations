output "lambda_function_name" {
  value = module.quota_manager.function_name
}

output "lambda_function_arn" {
  value = module.quota_manager.function_arn
}

output "lambda_role_arn" {
  value = module.quota_manager.role_arn
}

output "sns_topic_arn" {
  value = aws_sns_topic.quota_notifications.arn
}

output "sns_to_slack_function_name" {
  value = module.sns_to_slack.function_name
}

output "sqs_dlq_arn" {
  value = aws_sqs_queue.lambda_dlq.arn
}

output "target_regions" {
  value = local.target_regions
}

output "quota_config" {
  value = local.quota_config
} 