variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications"
  type        = string
  default     = "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
}

variable "slack_channel_name" {
  description = "Slack channel name for notifications"
  type        = string
  default     = "#ccoe-notifications"
}