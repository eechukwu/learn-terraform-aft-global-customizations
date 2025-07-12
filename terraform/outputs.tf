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

output "target_regions" {
  value = local.target_regions
}

output "quota_config" {
  value = local.quota_config
}

output "slack_function_arn" {
  value = aws_lambda_function.sns_to_slack.arn
} 