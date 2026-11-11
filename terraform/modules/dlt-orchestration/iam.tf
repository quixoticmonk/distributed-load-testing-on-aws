################################################################################
# Per-function IAM
# Statements are translated from the synthesized upstream template. Two deliberate
# changes: CloudWatch Logs writes are scoped to each function's own log group
# (upstream grants /aws/lambda/*), and the non-existent s3:HeadObject action is dropped.
################################################################################

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "function" {
  for_each = local.functions

  name_prefix        = "${substr("${var.name}-${each.key}", 0, 37)}-"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json

  tags = local.tags
}

data "aws_iam_policy_document" "logs" {
  for_each = local.functions

  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.function[each.key].arn}:*"]
  }
}

locals {
  scenarios_table_rw = ["dynamodb:DeleteItem", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Scan", "dynamodb:UpdateItem"]
  history_table_rw   = ["dynamodb:BatchWriteItem", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query", "dynamodb:UpdateItem"]

  function_policy = {
    metrics-emitter       = data.aws_iam_policy_document.logs["metrics-emitter"].json
    orphan-cleanup        = data.aws_iam_policy_document.orphan_cleanup.json
    regional-sync         = data.aws_iam_policy_document.regional_sync.json
    results-parser        = data.aws_iam_policy_document.results_parser.json
    sfn-failure-handler   = data.aws_iam_policy_document.sfn_failure_handler.json
    stabilization-checker = data.aws_iam_policy_document.stabilization_checker.json
    start-command         = data.aws_iam_policy_document.start_command.json
    task-canceler         = data.aws_iam_policy_document.task_canceler.json
    task-failure-handler  = data.aws_iam_policy_document.task_failure_handler.json
    task-runner           = data.aws_iam_policy_document.task_runner.json
    task-status-checker   = data.aws_iam_policy_document.task_status_checker.json
    test-cleanup          = data.aws_iam_policy_document.test_cleanup.json
    test-metadata-updater = data.aws_iam_policy_document.test_metadata_updater.json
  }
}

resource "aws_iam_role_policy" "function" {
  for_each = local.functions

  name   = "${each.key}-policy"
  role   = aws_iam_role.function[each.key].id
  policy = local.function_policy[each.key]
}

data "aws_iam_policy_document" "put_metric_data" {
  statement {
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["distributed-load-testing"]
    }
  }
}

data "aws_iam_policy_document" "task_runner" {
  source_policy_documents = [
    data.aws_iam_policy_document.logs["task-runner"].json,
    data.aws_iam_policy_document.put_metric_data.json,
  ]

  statement {
    sid       = "EcsUnscoped"
    actions   = ["ecs:DeregisterTaskDefinition", "ecs:DescribeTaskDefinition", "ecs:ListTaskDefinitions", "ecs:ListTasks"]
    resources = ["*"]
  }

  statement {
    sid = "EcsTagScoped"
    actions = [
      "ecs:CreateService",
      "ecs:DeleteService",
      "ecs:DeleteTaskDefinitions",
      "ecs:DescribeServices",
      "ecs:DescribeTasks",
      "ecs:RegisterTaskDefinition",
      "ecs:RunTask",
      "ecs:TagResource",
      "ecs:UpdateService",
      "logs:DescribeMetricFilters",
      "logs:PutMetricFilter",
    ]
    resources = ["*"]

    condition {
      test     = local.ecs_tag_condition.test
      variable = local.ecs_tag_condition.variable
      values   = local.ecs_tag_condition.values
    }
  }

  statement {
    sid       = "ScenarioResults"
    actions   = ["s3:PutObject"]
    resources = ["${var.scenarios_bucket_arn}/*"]
  }

  # Regional runners add their own role ARNs through a separate policy (see dlt-region).
  statement {
    sid       = "PassHubTaskRoles"
    actions   = ["iam:PassRole"]
    resources = [var.ecs_task_execution_role_arn, var.ecs_task_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid       = "Dashboards"
    actions   = ["cloudwatch:PutDashboard"]
    resources = [local.dashboard_arn]
  }

  statement {
    sid       = "ScenariosTable"
    actions   = local.scenarios_table_rw
    resources = [var.scenarios_table_arn]
  }
}

data "aws_iam_policy_document" "task_status_checker" {
  source_policy_documents = [data.aws_iam_policy_document.logs["task-status-checker"].json]

  statement {
    actions   = ["ecs:DescribeTasks", "ecs:ListTasks"]
    resources = ["*"]
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [var.scenarios_bucket_arn]
  }

  statement {
    actions   = local.scenarios_table_rw
    resources = [var.scenarios_table_arn]
  }
}

data "aws_iam_policy_document" "results_parser" {
  source_policy_documents = [data.aws_iam_policy_document.logs["results-parser"].json]

  statement {
    actions   = ["cloudwatch:GetMetricWidgetImage"]
    resources = ["*"]
  }

  statement {
    actions   = ["logs:DeleteMetricFilter"]
    resources = ["*"]

    condition {
      test     = local.ecs_tag_condition.test
      variable = local.ecs_tag_condition.variable
      values   = local.ecs_tag_condition.values
    }
  }

  statement {
    actions   = ["s3:GetObject", "s3:ListBucket", "s3:PutObject"]
    resources = [var.scenarios_bucket_arn, "${var.scenarios_bucket_arn}/*"]
  }

  statement {
    actions   = local.history_table_rw
    resources = [var.history_table_arn, "${var.history_table_arn}/index/*"]
  }

  statement {
    actions   = local.scenarios_table_rw
    resources = [var.scenarios_table_arn]
  }
}

data "aws_iam_policy_document" "test_cleanup" {
  source_policy_documents = [
    data.aws_iam_policy_document.logs["test-cleanup"].json,
    data.aws_iam_policy_document.put_metric_data.json,
  ]

  statement {
    actions   = ["ecs:DeregisterTaskDefinition", "ecs:ListTaskDefinitions", "ecs:ListTasks"]
    resources = ["*"]
  }

  statement {
    actions = [
      "ecs:DeleteService",
      "ecs:DeleteTaskDefinitions",
      "ecs:DescribeServices",
      "ecs:UpdateService",
      "logs:DeleteMetricFilter",
      "logs:DescribeMetricFilters",
    ]
    resources = ["*"]

    condition {
      test     = local.ecs_tag_condition.test
      variable = local.ecs_tag_condition.variable
      values   = local.ecs_tag_condition.values
    }
  }

  statement {
    actions   = ["dynamodb:UpdateItem"]
    resources = [var.scenarios_table_arn, var.history_table_arn]
  }

  statement {
    actions   = ["dynamodb:PutItem"]
    resources = [var.history_table_arn]
  }
}

data "aws_iam_policy_document" "stabilization_checker" {
  source_policy_documents = [data.aws_iam_policy_document.logs["stabilization-checker"].json]

  statement {
    actions   = ["ecs:DescribeServices"]
    resources = ["*"]

    condition {
      test     = local.ecs_tag_condition.test
      variable = local.ecs_tag_condition.variable
      values   = local.ecs_tag_condition.values
    }
  }
}

data "aws_iam_policy_document" "start_command" {
  source_policy_documents = [data.aws_iam_policy_document.logs["start-command"].json]

  statement {
    actions   = ["s3:PutObject"]
    resources = ["${var.scenarios_bucket_arn}/start-signal/*"]
  }
}

data "aws_iam_policy_document" "regional_sync" {
  source_policy_documents = [data.aws_iam_policy_document.logs["regional-sync"].json]

  statement {
    actions   = ["dynamodb:UpdateItem"]
    resources = [var.scenarios_table_arn]
  }
}

data "aws_iam_policy_document" "test_metadata_updater" {
  source_policy_documents = [data.aws_iam_policy_document.logs["test-metadata-updater"].json]

  statement {
    actions   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
    resources = [var.scenarios_table_arn]
  }

  statement {
    actions   = ["dynamodb:UpdateItem"]
    resources = [var.history_table_arn]
  }
}

data "aws_iam_policy_document" "task_canceler" {
  source_policy_documents = [data.aws_iam_policy_document.logs["task-canceler"].json]

  statement {
    actions   = ["dynamodb:UpdateItem"]
    resources = [var.scenarios_table_arn]
  }

  statement {
    actions   = ["dynamodb:PutItem"]
    resources = [var.history_table_arn]
  }

  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [local.function_arn["test-cleanup"]]
  }

  statement {
    actions   = ["states:ListExecutions"]
    resources = [local.state_machine_arn]
  }

  statement {
    actions   = ["states:DescribeExecution", "states:StopExecution"]
    resources = [local.execution_arn_glob]
  }
}

data "aws_iam_policy_document" "orphan_cleanup" {
  source_policy_documents = [
    data.aws_iam_policy_document.logs["orphan-cleanup"].json,
    data.aws_iam_policy_document.put_metric_data.json,
  ]

  statement {
    actions   = ["ecs:ListServices"]
    resources = ["*"]
  }

  statement {
    actions   = ["ecs:DeleteService", "ecs:DescribeServices", "ecs:UpdateService"]
    resources = ["*"]

    condition {
      test     = local.ecs_tag_condition.test
      variable = local.ecs_tag_condition.variable
      values   = local.ecs_tag_condition.values
    }
  }

  statement {
    actions   = ["dynamodb:Scan"]
    resources = [var.scenarios_table_arn]
  }

  statement {
    actions   = ["states:ListExecutions"]
    resources = [local.state_machine_arn]
  }
}

data "aws_iam_policy_document" "sfn_failure_handler" {
  source_policy_documents = [data.aws_iam_policy_document.logs["sfn-failure-handler"].json]

  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [local.function_arn["test-cleanup"]]
  }

  statement {
    actions   = ["states:DescribeExecution"]
    resources = [local.execution_arn_glob]
  }
}

data "aws_iam_policy_document" "task_failure_handler" {
  source_policy_documents = [
    data.aws_iam_policy_document.logs["task-failure-handler"].json,
    data.aws_iam_policy_document.put_metric_data.json,
  ]

  statement {
    actions   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
    resources = [var.scenarios_table_arn]
  }
}
