# Output values for Lambda quota management
output "lambda_quota_manager" {
  description = "Lambda function details"
  value = {
    function_name = aws_lambda_function.quota_manager.function_name
    function_arn  = aws_lambda_function.quota_manager.arn
    log_group     = aws_cloudwatch_log_group.quota_lambda_logs.name
  }
}

output "quota_request_results" {
  description = "Results from quota request execution"
  value = jsondecode(aws_lambda_invocation.quota_request.result)
}

output "quota_management_summary" {
  description = "Summary of quota management configuration"
  value = {
    target_regions = local.target_regions
    total_regions  = length(local.target_regions)
    quota_details = {
      service_code = local.quota_config.service_code
      quota_code   = local.quota_config.quota_code
      quota_value  = local.quota_config.quota_value
    }
    lambda_function = local.lambda_config.function_name
  }
}

output "operational_commands" {
  description = "Commands for operational management"
  value = {
    check_quotas = "aws lambda invoke --function-name ${aws_lambda_function.quota_manager.function_name} --qualifier live --payload '{\"action\":\"check_status\"}' response.json"
    view_logs = "aws logs tail /aws/lambda/${aws_lambda_function.quota_manager.function_name} --follow"
  }
}