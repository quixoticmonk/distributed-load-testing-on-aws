variable "access_log_retention_in_days" {
  description = "Days to keep S3 and CloudFront access logs. Upstream never expires them."
  type        = number
  default     = 365
}

variable "admin_email" {
  description = "Email for the initial console administrator. Cognito sends the temporary password here."
  type        = string

  validation {
    condition     = can(regex("^[_A-Za-z0-9-+]+(\\.[_A-Za-z0-9-]+)*@[A-Za-z0-9-]+(\\.[A-Za-z0-9]+)*(\\.[A-Za-z]{2,})$", var.admin_email))
    error_message = "admin_email must be a valid email address."
  }
}

variable "admin_name" {
  description = "Username for the initial console administrator."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.admin_name))
    error_message = "admin_name may contain only letters, digits and hyphens."
  }
}

variable "api_endpoint_type" {
  description = "API Gateway endpoint type. Upstream uses EDGE (REGIONAL in GovCloud)."
  type        = string
  default     = "EDGE"

  validation {
    condition     = contains(["EDGE", "REGIONAL"], var.api_endpoint_type)
    error_message = "api_endpoint_type must be EDGE or REGIONAL."
  }
}

variable "artifacts_dir" {
  description = "Directory produced by `make build`: lambda/<name>.zip, webui/, jmeter/jmeter-bundle.tgz."
  type        = string
}

variable "console_mode" {
  description = "cloudfront: host the web console on S3 + CloudFront (upstream default). headless: API and auth only; host the console yourself."
  type        = string
  default     = "cloudfront"

  validation {
    condition     = contains(["cloudfront", "headless"], var.console_mode)
    error_message = "console_mode must be cloudfront or headless."
  }
}

variable "console_web_acl_arn" {
  description = "Optional WAFv2 web ACL ARN (CLOUDFRONT scope) for the console distribution. Upstream attaches none."
  type        = string
  default     = null
}

variable "deploy_mcp_server" {
  description = "Deploy the optional MCP server (AgentCore Gateway + tool Lambda) for AI-assisted analysis."
  type        = bool
  default     = false
}

variable "egress_cidr_block" {
  description = "CIDR block load generator tasks may send traffic to. Narrow this to the system under test where possible."
  type        = string
  default     = "0.0.0.0/0"
}

variable "enable_deletion_protection" {
  description = "Turn on deletion protection for DynamoDB tables and the Cognito user pool, and keep data buckets on destroy."
  type        = bool
  default     = false
}

variable "existing_subnet_ids" {
  description = "Two existing subnet IDs for load generator tasks. Required with existing_vpc_id."
  type        = list(string)
  default     = []
}

variable "existing_vpc_id" {
  description = "Existing VPC for load generator tasks. When null a dedicated VPC with two public subnets is created."
  type        = string
  default     = null
}

variable "external_console_urls" {
  description = "Origins (https://host) where you host the console when console_mode is headless. Used for Cognito callbacks and S3 CORS."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for u in var.external_console_urls : can(regex("^https://[^/]+$", u))])
    error_message = "external_console_urls entries must be https origins without a path, e.g. https://dlt.example.com."
  }
}

variable "kms_key_arn" {
  description = "Customer managed KMS key for the scenarios bucket and DynamoDB tables. Null uses AWS managed keys (upstream behavior). A CMK also needs key-policy grants for the ECS task roles in every region; this module does not add them."
  type        = string
  default     = null
}

variable "load_tester_images" {
  description = "Override container images per framework (keys: taurus, jmeter, k6, locust). Unset keys use the public AWS Solutions images at load_tester_image_tag."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.load_tester_images) : contains(["taurus", "jmeter", "k6", "locust"], k)])
    error_message = "load_tester_images keys must be taurus, jmeter, k6 or locust."
  }
}

variable "load_tester_image_tag" {
  description = "Tag for the public AWS Solutions load tester images. v4.3.5 pins the release; v4.3_stable follows patch releases."
  type        = string
  default     = "v4.3.5"
}

variable "log_retention_in_days" {
  description = "Retention for every log group the hub creates. Upstream uses 3653 (10 years)."
  type        = number
  default     = 3653
}

variable "manage_api_gateway_account" {
  description = "Set the account-wide API Gateway CloudWatch Logs role. Required once per account/region for stage logging; turn off if your landing zone already manages it."
  type        = bool
  default     = true
}

variable "mcp_access_mode" {
  description = "MCP tool scope: ReadOnly exposes query tools only; ReadWrite adds create/start/stop/schedule tools."
  type        = string
  default     = "ReadOnly"

  validation {
    condition     = contains(["ReadOnly", "ReadWrite"], var.mcp_access_mode)
    error_message = "mcp_access_mode must be ReadOnly or ReadWrite."
  }
}

variable "name" {
  description = "Deployment name. Prefix for every resource and the ECS cluster name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,31}$", var.name))
    error_message = "name must start with a lowercase letter, contain only lowercase letters, digits and hyphens, and be at most 32 characters."
  }
}

variable "oauth_additional_callback_urls" {
  description = "Extra OAuth callback/logout URLs for the console app client, e.g. http://localhost:3000 for local UI development or MCP client callbacks. Upstream ships a fixed list of localhost and third-party MCP client URLs; this module adds none by default."
  type        = list(string)
  default     = []
}

variable "solution_id" {
  description = "Solution ID. The DLT Lambdas scope ECS and Logs permissions on aws:ResourceTag/SolutionId, so this must stay SO0062 unless the app code changes."
  type        = string
  default     = "SO0062"
}

variable "solution_metrics_url" {
  description = "Endpoint the DLT Lambdas POST anonymized usage metrics to. Required by the app code; point it at an internal sink to stop calls to AWS Solutions."
  type        = string
  default     = "https://metrics.awssolutionsbuilder.com/generic"
}

variable "solution_version" {
  description = "Solution version reported by the API and console. Must match the upstream source the artifacts were built from."
  type        = string
  default     = "v4.3.5"
}

variable "subnet_cidr_blocks" {
  description = "Two subnet CIDRs for the created VPC."
  type        = list(string)
  default     = ["192.168.0.0/20", "192.168.16.0/20"]
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "user_pool_tier" {
  description = "Cognito feature plan. Upstream enables threat protection in ENFORCED mode, which requires PLUS. ESSENTIALS drops threat protection."
  type        = string
  default     = "PLUS"

  validation {
    condition     = contains(["ESSENTIALS", "PLUS"], var.user_pool_tier)
    error_message = "user_pool_tier must be ESSENTIALS or PLUS."
  }
}

variable "vpc_cidr_block" {
  description = "CIDR for the created VPC."
  type        = string
  default     = "192.168.0.0/16"
}
