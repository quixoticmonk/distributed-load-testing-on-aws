output "api_endpoint" {
  description = "DLT API endpoint."
  value       = module.hub.api_endpoint
}

output "console_url" {
  description = "Web console URL. The admin's temporary password arrives by email."
  value       = module.hub.console_url
}

output "mcp_endpoint" {
  description = "MCP endpoint (when enabled)."
  value       = module.hub.mcp_endpoint
}

output "regions" {
  description = "Regions available for load tests."
  value       = [module.hub.regional_inputs.region, module.region_spoke.region]
}
