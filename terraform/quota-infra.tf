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

# Data source for existing Lambda execution role
data "aws_iam_role" "lambda_execution" {
  name = "AWSAFTLambdaExecutionRole"
}

# Simple Lambda function using existing role
resource "aws_lambda_function" "quota_manager" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "aft-quota-manager-${data.aws_caller_identity.current.account_id}"
  role            = data.aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.12"
  timeout         = 300
  memory_size     = 256

  environment {
    variables = merge({
      TARGET_REGIONS = join(",", local.target_regions)
    }, 
    merge([
      for quota_name, quota_config in local.quota_config : {
        for key, value in quota_config : 
        "QUOTA_CONFIG_${upper(replace(quota_name, "-", "_"))}_${upper(key)}" => tostring(value)
      }
    ]...)
    )
  }

  tags = var.tags
}

# Archive the Lambda function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
} 