output "lambda_function_name" {
  value = module.quota_manager.function_name
}

output "lambda_function_arn" {
  value = module.quota_manager.function_arn
}

output "lambda_role_arn" {
  value = module.quota_manager.role_arn
}

output "target_regions" {
  value = local.target_regions
}

output "quota_config" {
  value = local.quota_config
} 