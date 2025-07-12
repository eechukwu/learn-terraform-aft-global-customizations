variable "tags" {
  type    = map(string)
  default = {}
}

variable "slack_token_ssm_parameter_name" {
  type    = string
  default = "/aft/quota-manager/slack-token"
}

variable "slack_channel_name" {
  type    = string
  default = "ccoe-notifications"
} 