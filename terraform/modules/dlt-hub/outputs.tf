output "api_endpoint" {
  description = "DLT REST API invoke URL (IAM / SigV4 authorized)."
  value       = module.api.api_endpoint
}

output "cognito_identity_pool_id" {
  description = "Cognito identity pool ID."
  value       = module.auth.identity_pool_id
}

output "cognito_user_pool_client_id" {
  description = "Console app client ID."
  value       = module.auth.console_client_id
}

output "cognito_user_pool_id" {
  description = "Cognito user pool ID."
  value       = module.auth.user_pool_id
}

output "console_bucket_name" {
  description = "Console asset bucket (null in headless mode)."
  value       = local.cloudfront ? module.console[0].bucket_name : null
}

output "console_url" {
  description = "Web console URL (null in headless mode)."
  value       = local.cloudfront ? module.console[0].console_url : null
}

output "ecs_cluster_name" {
  description = "Hub ECS cluster name."
  value       = module.load_runner.cluster_name
}

output "mcp_endpoint" {
  description = "MCP endpoint URL (null when deploy_mcp_server is false)."
  value       = var.deploy_mcp_server ? module.mcp[0].gateway_url : null
}

output "metadata_stack_name" {
  description = "CloudFormation metadata shim stack the API reads."
  value       = aws_cloudformation_stack.metadata.name
}

output "regional_inputs" {
  description = "Pass to dlt-region as `hub`."
  value = {
    iot_endpoint          = data.aws_iot_endpoint.this.endpoint_address
    region                = local.region
    scenarios_bucket_name = module.storage.scenarios_bucket_name
    scenarios_table_name  = module.storage.scenarios_table_name
    task_runner_role_name = module.orchestration.task_runner_role_name
  }
}

output "runtime_config" {
  description = "Contents of aws-exports.json. In headless mode, serve this at /aws-exports.json next to the console assets."
  value       = local.runtime_config
}

output "scenarios_bucket_name" {
  description = "Scenarios bucket name."
  value       = module.storage.scenarios_bucket_name
}

output "scenarios_table_name" {
  description = "Scenarios table name."
  value       = module.storage.scenarios_table_name
}

output "solution_uuid" {
  description = "Deployment UUID."
  value       = local.uuid
}

output "state_machine_arn" {
  description = "Test orchestration state machine ARN."
  value       = module.orchestration.state_machine_arn
}
