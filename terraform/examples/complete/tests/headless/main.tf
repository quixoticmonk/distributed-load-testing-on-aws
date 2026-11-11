# Test fixture: headless hub (self-hosted console) with a read-write MCP server.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.72"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

variable "admin_email" {
  description = "Initial console administrator email."
  type        = string
}

variable "deploy_mcp_server" {
  description = "Deploy the optional MCP server."
  type        = bool
  default     = true
}

output "console_url" {
  description = "Console URL (null in headless mode)."
  value       = module.hub.console_url
}

output "runtime_config" {
  description = "aws-exports.json content for the self-hosted console."
  value       = module.hub.runtime_config
}

module "hub" {
  source = "../../../../modules/dlt-hub"

  name                  = "dlt-headless"
  admin_email           = var.admin_email
  admin_name            = "dlt-admin"
  artifacts_dir         = abspath("${path.module}/../../../../build")
  console_mode          = "headless"
  deploy_mcp_server     = var.deploy_mcp_server
  external_console_urls = ["https://dlt.example.internal"]
  mcp_access_mode       = "ReadWrite"
}
