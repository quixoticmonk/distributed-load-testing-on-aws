data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  tags = merge(var.tags, { SolutionId = var.solution_id })

  # key => timeout/memory, mirroring source/infrastructure/lib/back-end/test-task-lambdas.ts
  functions = {
    metrics-emitter       = { description = "Sends operational metrics for test lifecycle events", timeout = 15, memory = 128 }
    orphan-cleanup        = { description = "Hourly scan for orphaned ECS services not associated with active tests", timeout = 900, memory = 128 }
    regional-sync         = { description = "Validates all regions are READY and emits sync metric", timeout = 30, memory = 128 }
    results-parser        = { description = "Result parser for indexing xml test results to DynamoDB", timeout = 900, memory = 1024 }
    sfn-failure-handler   = { description = "Invokes test-cleanup when the step function fails", timeout = 120, memory = 128 }
    stabilization-checker = { description = "Checks ECS service stabilization status", timeout = 60, memory = 128 }
    start-command         = { description = "Writes S3 start marker so ECS tasks begin test execution", timeout = 60, memory = 128 }
    task-canceler         = { description = "Coordinates test cancellation and invokes test-cleanup per region", timeout = 300, memory = 128 }
    task-failure-handler  = { description = "Handles ECS task failure events and tracks failure threshold", timeout = 30, memory = 128 }
    task-runner           = { description = "Task runner for ECS task definitions", timeout = 900, memory = 128 }
    task-status-checker   = { description = "Task status checker for running checks and S3 completion monitoring", timeout = 300, memory = 128 }
    test-cleanup          = { description = "Cleans up ECS resources for one region and sets final DDB status", timeout = 900, memory = 128 }
    test-metadata-updater = { description = "Updates scenario and history records with current test status", timeout = 30, memory = 128 }
  }

  # Names and ARNs are computed so functions that need the state machine ARN and the
  # state machine that needs function ARNs do not form a dependency cycle.
  function_name      = { for k in keys(local.functions) : k => "${var.name}-${k}" }
  function_arn       = { for k, n in local.function_name : k => "arn:${local.partition}:lambda:${local.region}:${local.account_id}:function:${n}" }
  state_machine_name = "${var.name}-task-runner"
  state_machine_arn  = "arn:${local.partition}:states:${local.region}:${local.account_id}:stateMachine:${local.state_machine_name}"
  execution_arn_glob = "arn:${local.partition}:states:${local.region}:${local.account_id}:execution:${local.state_machine_name}:*"

  # Every function gets the union of the variables the upstream functions read.
  # Unused variables are harmless; per-function lists drift easily when upstream changes.
  function_env = merge(var.common_env, {
    HISTORY_TABLE     = var.history_table_name
    MAIN_STACK_REGION = local.region
    SCENARIOS_BUCKET  = var.scenarios_bucket_name
    SCENARIOS_TABLE   = var.scenarios_table_name
    STATE_MACHINE_ARN = local.state_machine_arn
    TEST_CLEANUP_ARN  = local.function_arn["test-cleanup"]
  })

  ecs_tag_condition = {
    test     = "StringEquals"
    variable = "aws:ResourceTag/SolutionId"
    values   = [var.solution_id]
  }

  dashboard_arn = "arn:${local.partition}:cloudwatch::${local.account_id}:dashboard/EcsLoadTesting*"
}
