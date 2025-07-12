variable "tags" {
  type    = map(string)
  default = {}
}

variable "aft_exec_role_arn" {
  description = "AFT Execution Role ARN"
  type        = string
} 