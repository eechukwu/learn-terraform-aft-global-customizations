output "lambda_function_name" {
  value = aws_lambda_function.quota_manager.function_name
}

output "lambda_function_arn" {
  value = aws_lambda_function.quota_manager.arn
}

output "lambda_role_arn" {
  value = aws_iam_role.lambda_role.arn
}

output "target_regions" {
  value = local.target_regions
}

output "quota_config" {
  value = local.quota_config
} 