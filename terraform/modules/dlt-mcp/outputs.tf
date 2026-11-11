output "gateway_url" {
  description = "MCP endpoint URL."
  value       = aws_bedrockagentcore_gateway.this.gateway_url
}

output "m2m_client_id" {
  description = "Machine-to-machine Cognito client ID (client_credentials). Fetch the secret from Cognito; it is not exported."
  value       = aws_cognito_user_pool_client.m2m.id
}
