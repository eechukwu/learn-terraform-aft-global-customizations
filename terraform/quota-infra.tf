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

module "quota_manager" {
  source = "github.com/eechukwu/tf-aws-lambda-develop"

  function_name = "aft-quota-manager-${data.aws_caller_identity.current.account_id}"
  description   = "AFT Quota Manager"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = "300"
  memory_size   = "256"
  source_path   = "${path.module}"

  tags = var.tags

  # Disable automatic IAM role creation
  create_role = false
  lambda_role = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AWSAFTAdmin"
  
  # Disable automatic policy attachment
  attach_policy = false
  
  reserved_concurrent_executions = "5"
  
  # Disable automatic log group management
  manage_log_group = false

  environment = {
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
}

data "aws_iam_policy_document" "quota_manager" {
  statement {
    sid = "ServiceQuotasPermissions"
    effect = "Allow"
    actions = [
      "servicequotas:GetServiceQuota",
      "servicequotas:RequestServiceQuotaIncrease",
      "servicequotas:ListRequestedServiceQuotaChangeHistory",
      "servicequotas:GetRequestedServiceQuotaChange"
    ]
    resources = ["*"]
  }

  statement {
    sid = "ServiceLinkedRole"
    effect = "Allow"
    actions = [
      "iam:CreateServiceLinkedRole"
    ]
    resources = [
      "arn:aws:iam::*:role/aws-service-role/servicequotas.amazonaws.com/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["servicequotas.amazonaws.com"]
    }
  }
} 