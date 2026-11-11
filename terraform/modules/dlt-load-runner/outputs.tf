output "cluster_arn" {
  description = "ECS cluster ARN for load generator tasks."
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "ECS cluster name for load generator tasks."
  value       = aws_ecs_cluster.this.name
}

output "log_group_arn" {
  description = "ECS task log group ARN."
  value       = aws_cloudwatch_log_group.tasks.arn
}

output "log_group_name" {
  description = "ECS task log group name."
  value       = aws_cloudwatch_log_group.tasks.name
}

output "real_time_data_publisher_function_name" {
  description = "Real-time data publisher Lambda function name."
  value       = aws_lambda_function.real_time_data_publisher.function_name
}

output "real_time_data_publisher_log_group_name" {
  description = "Real-time data publisher Lambda log group name."
  value       = aws_cloudwatch_log_group.real_time_data_publisher.name
}

output "region" {
  description = "Region this load runner is deployed in."
  value       = data.aws_region.current.region
}

output "security_group_id" {
  description = "Security group attached to load generator tasks."
  value       = aws_security_group.tasks.id
}

output "subnet_ids" {
  description = "Two subnets load generator tasks run in."
  value       = local.subnet_ids
}

output "task_definition_arns" {
  description = "Framework task definition ARNs keyed by taurus, jmeter, k6, locust (hub only; empty otherwise)."
  value       = { for k, v in aws_ecs_task_definition.this : k => v.arn }
}

output "task_execution_role_arn" {
  description = "ECS task execution role ARN."
  value       = aws_iam_role.task_execution.arn
}

output "task_role_arn" {
  description = "ECS task role ARN."
  value       = aws_iam_role.task.arn
}

output "vpc_id" {
  description = "VPC load generator tasks run in."
  value       = local.vpc_id
}
