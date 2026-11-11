output "api_endpoint" {
  description = "Invoke URL of the prod stage, e.g. https://<id>.execute-api.<region>.amazonaws.com/prod."
  value       = aws_api_gateway_stage.prod.invoke_url
}

output "api_lambda_log_group_name" {
  description = "api-services Lambda log group name."
  value       = aws_cloudwatch_log_group.api_lambda.name
}

output "execution_arn" {
  description = "REST API execution ARN (for IAM policies granting execute-api:Invoke)."
  value       = aws_api_gateway_rest_api.this.execution_arn
}

output "rest_api_id" {
  description = "REST API ID."
  value       = aws_api_gateway_rest_api.this.id
}

output "stage_name" {
  description = "Stage name."
  value       = aws_api_gateway_stage.prod.stage_name
}
