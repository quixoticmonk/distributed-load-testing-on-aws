variable "admin_email" {
  description = "Initial console administrator email."
  type        = string
}

variable "admin_name" {
  description = "Initial console administrator username."
  type        = string
  default     = "dlt-admin"
}

variable "deploy_mcp_server" {
  description = "Deploy the optional MCP server."
  type        = bool
  default     = false
}

variable "egress_cidr_block" {
  description = "CIDR load generators may reach. Narrow this to the system under test."
  type        = string
  default     = "0.0.0.0/0"
}

variable "environment" {
  description = "Environment label for tagging."
  type        = string
  default     = "dev"
}

variable "hub_region" {
  description = "Hub region (console, API, orchestration, and a load runner)."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Deployment name (lowercase, <= 32 chars)."
  type        = string
  default     = "dlt"
}

variable "spoke_region" {
  description = "Additional load-testing region."
  type        = string
  default     = "us-west-2"
}
