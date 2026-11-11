output "agent_spaces_table_arn" {
  description = "DevOps Agent spaces table ARN."
  value       = aws_dynamodb_table.agent_spaces.arn
}

output "agent_spaces_table_name" {
  description = "DevOps Agent spaces table name."
  value       = aws_dynamodb_table.agent_spaces.name
}

output "history_table_arn" {
  description = "Test run history table ARN."
  value       = aws_dynamodb_table.history.arn
}

output "history_table_gsi_name" {
  description = "History table GSI used by the API to list runs by start time."
  value       = local.history_gsi_name
}

output "history_table_name" {
  description = "Test run history table name."
  value       = aws_dynamodb_table.history.name
}

output "investigations_table_arn" {
  description = "DevOps Agent investigations table ARN."
  value       = aws_dynamodb_table.investigations.arn
}

output "investigations_table_name" {
  description = "DevOps Agent investigations table name."
  value       = aws_dynamodb_table.investigations.name
}

output "logs_bucket_id" {
  description = "Access log bucket name."
  value       = aws_s3_bucket.logs.id
}

output "logs_bucket_regional_domain_name" {
  description = "Access log bucket regional domain name (CloudFront logging target)."
  value       = aws_s3_bucket.logs.bucket_regional_domain_name
}

output "scenarios_bucket_arn" {
  description = "Scenarios bucket ARN."
  value       = aws_s3_bucket.scenarios.arn
}

output "scenarios_bucket_name" {
  description = "Scenarios bucket name."
  value       = aws_s3_bucket.scenarios.id
}

output "scenarios_table_arn" {
  description = "Scenarios table ARN."
  value       = aws_dynamodb_table.scenarios.arn
}

output "scenarios_table_name" {
  description = "Scenarios table name. Regions register themselves here as region-<region> items."
  value       = aws_dynamodb_table.scenarios.name
}
