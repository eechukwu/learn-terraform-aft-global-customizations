variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications"
  type        = string
  default     = "https://hooks.slack.com/services/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"
}

variable "slack_channel_name" {
  description = "Slack channel name for notifications"
  type        = string
  default     = "#eechukwu"
}