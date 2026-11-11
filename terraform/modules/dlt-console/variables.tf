variable "cognito_domain_host" {
  description = "Cognito hosted domain host (no scheme). Added to the CSP default-src, script-src, connect-src and form-action directives."
  type        = string
}

variable "csp_connect_src_extra" {
  description = "Extra connect-src origins. Upstream allows https://metrics.awssolutionsbuilder.com for console usage metrics."
  type        = list(string)
  default     = ["https://metrics.awssolutionsbuilder.com"]
}

variable "logs_bucket_id" {
  description = "Access log bucket name."
  type        = string
}

variable "logs_bucket_regional_domain_name" {
  description = "Access log bucket regional domain name for CloudFront standard logs."
  type        = string
}

variable "name" {
  description = "Deployment name used as the resource prefix."
  type        = string
}

variable "price_class" {
  description = "CloudFront price class."
  type        = string
  default     = "PriceClass_All"
}

variable "runtime_config" {
  description = "Object written to /aws-exports.json (Cognito, API and IoT settings the console reads at startup)."
  type        = map(string)
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

variable "web_acl_arn" {
  description = "Optional WAFv2 web ACL (CLOUDFRONT scope, us-east-1) to attach. Upstream attaches none."
  type        = string
  default     = null
}

variable "webui_dir" {
  description = "Built web console directory (make webui)."
  type        = string
}
