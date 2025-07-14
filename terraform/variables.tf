variable "slack_channel_name" {
  description = "Slack channel name for notifications."
  type        = string
  default     = "#ccoe-notifications"
}

variable "cloud_services_slack_topic_arn" {
  description = "ARN of the Cloud Services Slack SNS topic."
  type        = string
  default     = "arn:aws:sns:eu-west-1:CLOUD-SERVICES-ACCOUNT-ID:cloud-services-slack"
}

variable "slack_notification_region" {
  description = "Region for Slack notifications."
  type        = string
  default     = "eu-west-1"
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources."
  type        = map(any)
  default     = {}
}