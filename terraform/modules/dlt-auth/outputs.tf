output "console_client_id" {
  description = "Console app client ID."
  value       = aws_cognito_user_pool_client.console.id
}

output "domain_host" {
  description = "Cognito hosted domain host name."
  value       = "${aws_cognito_user_pool_domain.this.domain}.${local.partition == "aws-us-gov" ? "auth-fips" : "auth"}.${local.region}.amazoncognito.com"
}

output "identity_pool_id" {
  description = "Identity pool ID."
  value       = aws_cognito_identity_pool.this.id
}

output "iot_policy_name" {
  description = "IoT policy the console attaches to each Cognito identity."
  value       = aws_iot_policy.this.name
}

output "user_pool_arn" {
  description = "User pool ARN."
  value       = aws_cognito_user_pool.this.arn
}

output "user_pool_id" {
  description = "User pool ID."
  value       = aws_cognito_user_pool.this.id
}
