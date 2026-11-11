variable "access_mode" {
  description = "ReadOnly exposes query tools; ReadWrite adds create/start/stop/schedule tools and write API access."
  type        = string
  default     = "ReadOnly"

  validation {
    condition     = contains(["ReadOnly", "ReadWrite"], var.access_mode)
    error_message = "access_mode must be ReadOnly or ReadWrite."
  }
}

variable "allowed_client_ids" {
  description = "Cognito app client IDs whose tokens the gateway accepts (the console client, so users can sign in from an MCP client)."
  type        = list(string)
  default     = []
}

variable "api_endpoint" {
  description = "DLT API invoke URL including stage."
  type        = string
}

variable "api_execution_arn" {
  description = "DLT REST API execution ARN."
  type        = string
}

variable "common_env" {
  description = "Environment variables shared by every DLT Lambda."
  type        = map(string)
}

variable "lambda_zip" {
  description = "Path to the mcp-server Lambda zip."
  type        = string
}

variable "log_retention_in_days" {
  description = "Retention for the tool Lambda log group."
  type        = number
  default     = 3653
}

variable "name" {
  description = "Deployment name used as the resource prefix."
  type        = string
}

variable "scenarios_bucket_arn" {
  description = "Scenarios bucket ARN."
  type        = string
}

variable "scenarios_bucket_name" {
  description = "Scenarios bucket name (also stores the tool schema)."
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

variable "user_pool_id" {
  description = "Cognito user pool ID that issues gateway tokens."
  type        = string
}
