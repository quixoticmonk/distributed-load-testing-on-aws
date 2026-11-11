variable "common_env" {
  description = "Environment variables shared by every DLT Lambda (AWS_ACCOUNT_ID, METRIC_URL, SOLUTION_ID, UUID, VERSION)."
  type        = map(string)
}

variable "ecs_task_execution_role_arn" {
  description = "Hub ECS task execution role ARN (task-runner passes it to RunTask/CreateService)."
  type        = string
}

variable "ecs_task_role_arn" {
  description = "Hub ECS task role ARN."
  type        = string
}

variable "lambda_zips" {
  description = "Map of function key to zip path. Must include every key in local.functions."
  type        = map(string)
}

variable "log_retention_in_days" {
  description = "Retention for Lambda and Step Functions log groups."
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
  description = "Scenarios bucket name."
  type        = string
}

variable "history_table_arn" {
  description = "History table ARN."
  type        = string
}

variable "history_table_name" {
  description = "History table name."
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
  description = "Solution ID used in IAM tag conditions and the CloudWatch alarm dimension."
  type        = string
  default     = "SO0062"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
