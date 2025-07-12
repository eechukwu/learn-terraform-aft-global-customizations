variable "tags" {
  type    = map(string)
  default = {}
}

variable "slack_webhook_url" {
  type        = string
  description = "Slack webhook URL for notifications"
  default     = ""
}

variable "slack_channel_name" {
  type        = string
  description = "Slack channel name for notifications"
  default     = "ccoe-notifications"
} 