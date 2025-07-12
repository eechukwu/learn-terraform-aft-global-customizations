# IAM policy for AFT quota management
data "aws_iam_policy_document" "aft_quota_permissions" {
  statement {
    sid    = "QuotaManagementPermissions"
    effect = "Allow"
    
    actions = [
      "sqs:CreateQueue",
      "sqs:DeleteQueue",
      "sqs:GetQueueAttributes",
      "sqs:SetQueueAttributes",
      "sqs:TagQueue",
      "sqs:UntagQueue",
      "kms:CreateKey",
      "kms:DeleteKey",
      "kms:DescribeKey",
      "kms:CreateAlias",
      "kms:DeleteAlias",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:EnableKeyRotation",
      "events:PutRule",
      "events:DeleteRule",
      "events:PutTargets",
      "events:RemoveTargets",
      "events:TagResource",
      "events:UntagResource",
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:TagLogGroup",
      "lambda:CreateFunction",
      "lambda:DeleteFunction",
      "lambda:UpdateFunctionCode",
      "lambda:AddPermission",
      "lambda:CreateAlias",
      "lambda:TagResource",
      "lambda:PutFunctionConcurrency",
      "lambda:PutFunctionEventInvokeConfig",
      "iam:CreateRole",
      "iam:CreatePolicy",
      "iam:AttachRolePolicy",
      "iam:PutRolePolicy",
      "iam:PassRole",
      "iam:TagRole",
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:SetTopicAttributes",
      "sns:Subscribe",
      "sns:TagResource",
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:TagResource"
    ]
    
    resources = ["*"]
  }
}

# Attach policy to existing AWSAFTAdmin role
resource "aws_iam_role_policy" "aft_quota_management" {
  name   = "AFTQuotaManagementPolicy"
  role   = "AWSAFTAdmin"
  policy = data.aws_iam_policy_document.aft_quota_permissions.json
  
  lifecycle {
    create_before_destroy = true
  }
}