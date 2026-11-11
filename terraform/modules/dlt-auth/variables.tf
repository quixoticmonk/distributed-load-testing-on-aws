variable "additional_callback_urls" {
  description = "Extra OAuth callback/logout URLs (local development, MCP clients)."
  type        = list(string)
  default     = []
}

variable "admin_email" {
  description = "Initial administrator email."
  type        = string
}

variable "admin_name" {
  description = "Initial administrator username."
  type        = string
}

variable "api_execution_arn" {
  description = "REST API execution ARN."
  type        = string
}

variable "api_stage_name" {
  description = "REST API stage the console calls."
  type        = string
  default     = "prod"
}

variable "console_urls" {
  description = "Console origins (https://host) used for OAuth callbacks and the invite email."
  type        = list(string)
  default     = []
}

variable "domain_prefix" {
  description = "Cognito hosted domain prefix. Must be globally unique within the region."
  type        = string
}

variable "enable_deletion_protection" {
  description = "Turn on Cognito user pool deletion protection."
  type        = bool
  default     = false
}

variable "log_retention_in_days" {
  description = "Retention for the Cognito log group."
  type        = number
  default     = 3653
}

variable "name" {
  description = "Deployment name used as the resource prefix."
  type        = string
}

variable "scenarios_bucket_arn" {
  description = "Scenarios bucket ARN (console uploads scripts and reads results)."
  type        = string
}

variable "solution_id" {
  description = "Solution ID tag value."
  type        = string
  default     = "SO0062"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "user_pool_tier" {
  description = "Cognito feature plan: ESSENTIALS or PLUS (PLUS enables threat protection)."
  type        = string
  default     = "PLUS"
}
