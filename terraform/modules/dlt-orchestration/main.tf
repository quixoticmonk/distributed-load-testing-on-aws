################################################################################
# Lambda functions
################################################################################

resource "aws_cloudwatch_log_group" "function" {
  for_each = local.functions

  name              = "/aws/lambda/${local.function_name[each.key]}"
  retention_in_days = var.log_retention_in_days

  tags = local.tags
}

resource "aws_lambda_function" "this" {
  for_each = local.functions

  function_name    = local.function_name[each.key]
  description      = each.value.description
  role             = aws_iam_role.function[each.key].arn
  filename         = var.lambda_zips[each.key]
  source_code_hash = filebase64sha256(var.lambda_zips[each.key])
  handler          = "index.handler"
  runtime          = "nodejs24.x"
  architectures    = ["arm64"]
  memory_size      = each.value.memory
  timeout          = each.value.timeout

  environment {
    variables = local.function_env
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.function[each.key].name
  }

  tracing_config {
    mode = "PassThrough"
  }

  tags = local.tags

  depends_on = [aws_iam_role_policy.function]
}

################################################################################
# Step Functions state machine (test orchestration)
################################################################################

resource "aws_cloudwatch_log_group" "state_machine" {
  # The /aws/vendedlogs/ prefix avoids the CloudWatch Logs resource policy size limit.
  name              = "/aws/vendedlogs/states/${local.state_machine_name}"
  retention_in_days = var.log_retention_in_days

  tags = local.tags
}

data "aws_iam_policy_document" "states_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "state_machine" {
  name_prefix        = "${substr(var.name, 0, 24)}-sfn-"
  assume_role_policy = data.aws_iam_policy_document.states_trust.json

  tags = local.tags
}

locals {
  state_machine_functions = [
    "metrics-emitter",
    "regional-sync",
    "results-parser",
    "stabilization-checker",
    "start-command",
    "task-runner",
    "task-status-checker",
    "test-cleanup",
    "test-metadata-updater",
  ]
}

data "aws_iam_policy_document" "state_machine" {
  statement {
    sid       = "InvokeStageFunctions"
    actions   = ["lambda:InvokeFunction"]
    resources = flatten([for k in local.state_machine_functions : [aws_lambda_function.this[k].arn, "${aws_lambda_function.this[k].arn}:*"]])
  }

  # Vended log delivery APIs do not support resource-level permissions.
  statement {
    sid = "LogDelivery"
    actions = [
      "logs:CreateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:DescribeLogGroups",
      "logs:DescribeResourcePolicies",
      "logs:GetLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:UpdateLogDelivery",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "XRay"
    actions   = ["xray:GetSamplingRules", "xray:GetSamplingTargets", "xray:PutTelemetryRecords", "xray:PutTraceSegments"]
    resources = ["*"]
  }

  # Distributed Map child executions.
  statement {
    sid       = "DistributedMapStart"
    actions   = ["states:StartExecution"]
    resources = [local.state_machine_arn]
  }

  statement {
    sid       = "DistributedMapManage"
    actions   = ["states:DescribeExecution", "states:StopExecution"]
    resources = [local.execution_arn_glob]
  }

  statement {
    sid       = "DistributedMapRedrive"
    actions   = ["states:RedriveExecution"]
    resources = ["arn:${local.partition}:states:${local.region}:${local.account_id}:execution:${local.state_machine_name}/*:*"]
  }
}

resource "aws_iam_role_policy" "state_machine" {
  name   = "state-machine-policy"
  role   = aws_iam_role.state_machine.id
  policy = data.aws_iam_policy_document.state_machine.json
}

resource "aws_sfn_state_machine" "this" {
  name     = local.state_machine_name
  role_arn = aws_iam_role.state_machine.arn

  definition = templatefile("${path.module}/templates/state-machine.json.tftpl", {
    account_id                = local.account_id
    metrics_emitter_arn       = aws_lambda_function.this["metrics-emitter"].arn
    partition                 = local.partition
    regional_sync_arn         = aws_lambda_function.this["regional-sync"].arn
    results_parser_arn        = aws_lambda_function.this["results-parser"].arn
    stabilization_checker_arn = aws_lambda_function.this["stabilization-checker"].arn
    start_command_arn         = aws_lambda_function.this["start-command"].arn
    task_runner_arn           = aws_lambda_function.this["task-runner"].arn
    task_status_checker_arn   = aws_lambda_function.this["task-status-checker"].arn
    test_cleanup_arn          = aws_lambda_function.this["test-cleanup"].arn
    test_status_updater_arn   = aws_lambda_function.this["test-metadata-updater"].arn
    uuid                      = var.common_env["UUID"]
  })

  logging_configuration {
    include_execution_data = false
    level                  = "ALL"
    log_destination        = "${aws_cloudwatch_log_group.state_machine.arn}:*"
  }

  tracing_configuration {
    enabled = true
  }

  tags = local.tags

  depends_on = [aws_iam_role_policy.state_machine]
}

################################################################################
# EventBridge: failure handling and orphan cleanup
################################################################################

locals {
  event_rules = {
    ecs-task-stopped = {
      description = "Routes ECS task STOPPED events to the Task Failure Handler for threshold tracking"
      function    = "task-failure-handler"
      pattern = {
        source        = ["aws.ecs"]
        "detail-type" = ["ECS Task State Change"]
        detail        = { lastStatus = ["STOPPED"] }
      }
      schedule = null
    }
    sfn-failure = {
      description = "Routes Step Function execution failures to the SFN Failure Handler for ECS cleanup"
      function    = "sfn-failure-handler"
      # Terminal failure states only; RUNNING / PENDING_REDRIVE must not trigger cleanup.
      pattern = {
        source        = ["aws.states"]
        "detail-type" = ["Step Functions Execution Status Change"]
        detail = {
          status          = ["FAILED", "TIMED_OUT", "ABORTED"]
          stateMachineArn = [local.state_machine_arn]
        }
      }
      schedule = null
    }
    orphan-cleanup = {
      description = "Hourly trigger for orphaned ECS service cleanup"
      function    = "orphan-cleanup"
      pattern     = null
      schedule    = "rate(1 hour)"
    }
  }
}

resource "aws_cloudwatch_event_rule" "this" {
  for_each = local.event_rules

  name                = "${var.name}-${each.key}"
  description         = each.value.description
  event_pattern       = each.value.pattern == null ? null : jsonencode(each.value.pattern)
  schedule_expression = each.value.schedule

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "this" {
  for_each = local.event_rules

  rule = aws_cloudwatch_event_rule.this[each.key].name
  arn  = aws_lambda_function.this[each.value.function].arn
}

resource "aws_lambda_permission" "events" {
  for_each = local.event_rules

  statement_id  = "AllowEventBridge-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this[each.value.function].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.this[each.key].arn
}

resource "aws_cloudwatch_metric_alarm" "orphan_cleanup_failure" {
  alarm_name          = "${var.name}-OrphanCleanupFailure"
  alarm_description   = "Orphan ECS service cleanup failed. Delete orphaned services manually to stop ongoing Fargate charges."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "OrphanCleanupFailures"
  namespace           = "distributed-load-testing"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "breaching"

  dimensions = {
    SolutionId = var.solution_id
  }

  tags = local.tags
}
