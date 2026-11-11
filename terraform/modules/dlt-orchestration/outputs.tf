output "function_arns" {
  description = "Function ARNs keyed by function key."
  value       = { for k, v in aws_lambda_function.this : k => v.arn }
}

output "function_names" {
  description = "Function names keyed by function key."
  value       = { for k, v in aws_lambda_function.this : k => v.function_name }
}

output "log_group_names" {
  description = "Lambda log group names keyed by function key."
  value       = { for k, v in aws_cloudwatch_log_group.function : k => v.name }
}

output "state_machine_arn" {
  description = "Test orchestration state machine ARN."
  value       = aws_sfn_state_machine.this.arn
}

output "task_canceler_arn" {
  description = "Task canceler function ARN (the API invokes it to stop tests)."
  value       = aws_lambda_function.this["task-canceler"].arn
}

output "task_runner_role_arn" {
  description = "Task runner role ARN. Each region grants it iam:PassRole on its ECS roles."
  value       = aws_iam_role.function["task-runner"].arn
}

output "task_runner_role_name" {
  description = "Task runner role name. dlt-region attaches its PassRole policy here."
  value       = aws_iam_role.function["task-runner"].name
}
