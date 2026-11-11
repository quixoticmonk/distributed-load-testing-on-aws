variable "access_log_retention_in_days" {
  description = "Days to keep S3 and CloudFront access logs. Upstream never expires them."
  type        = number
  default     = 365
}

variable "console_origins" {
  description = "Browser origins (https://host) allowed to call the scenarios bucket via CORS."
  type        = list(string)
  default     = []
}

variable "enable_deletion_protection" {
  description = "Turn on DynamoDB deletion protection and keep non-empty buckets on destroy."
  type        = bool
  default     = false
}

variable "jmeter_bundle_path" {
  description = "Local path to jmeter-bundle.tgz built by `make jmeter`."
  type        = string
}

variable "kms_key_arn" {
  description = "Customer managed KMS key for the scenarios bucket and DynamoDB tables. Null uses AWS managed keys (upstream behavior)."
  type        = string
  default     = null
}

variable "name" {
  description = "Deployment name used as the resource prefix."
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
