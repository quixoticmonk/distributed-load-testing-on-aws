variable "agent_spaces_table_arn" {
  description = "DevOps Agent spaces table ARN."
  type        = string
}

variable "agent_spaces_table_name" {
  description = "DevOps Agent spaces table name."
  type        = string
}

variable "common_env" {
  description = "Environment variables shared by every DLT Lambda."
  type        = map(string)
}

variable "ecs_task_execution_role_arn" {
  description = "Hub ECS task execution role ARN."
  type        = string
}

variable "ecs_task_role_arn" {
  description = "Hub ECS task role ARN."
  type        = string
}

variable "endpoint_type" {
  description = "API Gateway endpoint type: EDGE or REGIONAL."
  type        = string
  default     = "EDGE"

  validation {
    condition     = contains(["EDGE", "REGIONAL"], var.endpoint_type)
    error_message = "endpoint_type must be EDGE or REGIONAL."
  }
}

variable "history_table_arn" {
  description = "History table ARN."
  type        = string
}

variable "history_table_gsi_name" {
  description = "History table GSI name."
  type        = string
}

variable "history_table_name" {
  description = "History table name."
  type        = string
}

variable "investigations_table_arn" {
  description = "DevOps Agent investigations table ARN."
  type        = string
}

variable "investigations_table_name" {
  description = "DevOps Agent investigations table name."
  type        = string
}

variable "lambda_zip" {
  description = "Path to the api-services Lambda zip."
  type        = string
}

variable "log_retention_in_days" {
  description = "Retention for API access logs and the API Lambda log group."
  type        = number
  default     = 3653
}

variable "manage_api_gateway_account" {
  description = "Set the account-wide API Gateway CloudWatch Logs role. Only one stack per account/region should own this."
  type        = bool
  default     = true
}

variable "metadata_stack_id" {
  description = "ID of the CloudFormation metadata stack the API reads for /stack-info and /regions."
  type        = string
}

variable "metadata_stack_name" {
  description = "Name of the CloudFormation metadata stack."
  type        = string
}

variable "min_compatible_version" {
  description = "Oldest regional version the API accepts."
  type        = string
  default     = "4.3.0"
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
  description = "Scenarios bucket name."
  type        = string
}

variable "scenarios_table_arn" {
  description = "Scenarios table ARN."
  type        = string
}

variable "scenarios_table_name" {
  description = "Scenarios table name."
  type        = string
}

variable "solution_id" {
  description = "Solution ID used in IAM tag conditions."
  type        = string
  default     = "SO0062"
}

variable "state_machine_arn" {
  description = "Test orchestration state machine ARN."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "task_canceler_arn" {
  description = "Task canceler function ARN."
  type        = string
}
