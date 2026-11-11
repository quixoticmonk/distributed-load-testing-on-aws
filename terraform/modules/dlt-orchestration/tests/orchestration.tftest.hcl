# Plan-only, mocked. Checks function inventory, state machine wiring and event rules.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

variables {
  name                        = "dlt"
  common_env                  = { AWS_ACCOUNT_ID = "111111111111", METRIC_URL = "https://metrics.example.com", SOLUTION_ID = "SO0062", UUID = "u", VERSION = "v4.3.5" }
  ecs_task_execution_role_arn = "arn:aws:iam::111111111111:role/exec"
  ecs_task_role_arn           = "arn:aws:iam::111111111111:role/task"
  history_table_arn           = "arn:aws:dynamodb:us-east-1:111111111111:table/dlt-history"
  history_table_name          = "dlt-history"
  scenarios_bucket_arn        = "arn:aws:s3:::dlt-scenarios"
  scenarios_bucket_name       = "dlt-scenarios"
  scenarios_table_arn         = "arn:aws:dynamodb:us-east-1:111111111111:table/dlt-scenarios"
  scenarios_table_name        = "dlt-scenarios"
  lambda_zips = {
    for k in [
      "metrics-emitter", "orphan-cleanup", "regional-sync", "results-parser", "sfn-failure-handler",
      "stabilization-checker", "start-command", "task-canceler", "task-failure-handler", "task-runner",
      "task-status-checker", "test-cleanup", "test-metadata-updater",
    ] : k => "../../build/lambda/${k}.zip"
  }
}

run "wiring" {
  command = plan

  assert {
    condition     = length(aws_lambda_function.this) == 13
    error_message = "Expected 13 worker functions."
  }

  assert {
    condition     = aws_lambda_function.this["task-canceler"].environment[0].variables["STATE_MACHINE_ARN"] == "arn:aws:states:us-east-1:111111111111:stateMachine:dlt-task-runner"
    error_message = "Computed state machine ARN must match the real state machine name."
  }

  assert {
    condition     = aws_sfn_state_machine.this.name == "dlt-task-runner"
    error_message = "State machine name must match the computed ARN."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.this["sfn-failure"].event_pattern).detail.status == ["FAILED", "TIMED_OUT", "ABORTED"]
    error_message = "SFN failure rule must match terminal failure states only."
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this["orphan-cleanup"].schedule_expression == "rate(1 hour)"
    error_message = "Orphan cleanup must run hourly."
  }
}
