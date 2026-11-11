################################################################################
# api-services IAM, translated from the synthesized upstream template.
# Change from upstream: Logs writes are scoped to this function's log group.
################################################################################

data "aws_iam_policy_document" "api_lambda" {
  statement {
    sid       = "OwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.api_lambda.arn}:*"]
  }

  statement {
    sid       = "EcsTagScoped"
    actions   = ["ecs:DescribeTasks", "ecs:ListTasks", "ecs:RunTask", "ecs:TagResource", "logs:DeleteMetricFilter"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/SolutionId"
      values   = [var.solution_id]
    }
  }

  statement {
    sid = "EcsRead"
    actions = [
      "ecs:DescribeClusters",
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:DescribeTasks",
      "ecs:ListAccountSettings",
      "ecs:ListClusters",
      "ecs:ListTasks",
      "servicequotas:GetServiceQuota",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "PassTaskRoles"
    actions   = ["iam:PassRole"]
    resources = [var.ecs_task_execution_role_arn, var.ecs_task_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid       = "StartTests"
    actions   = ["states:StartExecution"]
    resources = [var.state_machine_arn]
  }

  statement {
    sid       = "CancelTests"
    actions   = ["lambda:InvokeFunction"]
    resources = [var.task_canceler_arn]
  }

  statement {
    sid       = "Dashboards"
    actions   = ["cloudwatch:DeleteDashboards"]
    resources = ["arn:${local.partition}:cloudwatch::${local.account_id}:dashboard/EcsLoadTesting*"]
  }

  # /stack-info and /regions read the metadata stack (see dlt-hub metadata.tf).
  # ListExports has no resource-level permissions.
  statement {
    sid       = "MetadataStack"
    actions   = ["cloudformation:DescribeStacks", "cloudformation:ListExports"]
    resources = ["*"]
  }

  statement {
    sid       = "ScenariosBucket"
    actions   = ["s3:GetObject", "s3:ListBucket", "s3:PutObject"]
    resources = [var.scenarios_bucket_arn, "${var.scenarios_bucket_arn}/*"]
  }

  statement {
    sid       = "ScenariosTable"
    actions   = ["dynamodb:DeleteItem", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Scan", "dynamodb:UpdateItem"]
    resources = [var.scenarios_table_arn]
  }

  statement {
    sid       = "HistoryTable"
    actions   = ["dynamodb:BatchWriteItem", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query", "dynamodb:UpdateItem"]
    resources = [var.history_table_arn, "${var.history_table_arn}/index/*"]
  }

  statement {
    sid       = "AgentSpacesTable"
    actions   = ["dynamodb:BatchGetItem", "dynamodb:DeleteItem", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Scan", "dynamodb:UpdateItem"]
    resources = [var.agent_spaces_table_arn]
  }

  statement {
    sid       = "InvestigationsTable"
    actions   = ["dynamodb:DeleteItem", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query", "dynamodb:UpdateItem"]
    resources = [var.investigations_table_arn]
  }

  # Legacy (v3) EventBridge rule schedules.
  statement {
    sid     = "LegacyEventRules"
    actions = ["events:DeleteRule", "events:PutRule", "events:PutTargets", "events:RemoveTargets"]
    resources = [
      "arn:${local.partition}:events:${local.region}:${local.account_id}:rule/*Create",
      "arn:${local.partition}:events:${local.region}:${local.account_id}:rule/*Scheduled",
    ]
  }

  statement {
    sid       = "ListEventRules"
    actions   = ["events:ListRules"]
    resources = ["arn:${local.partition}:events:${local.region}:${local.account_id}:rule/*"]
  }

  statement {
    sid     = "Schedules"
    actions = ["scheduler:CreateSchedule", "scheduler:DeleteSchedule", "scheduler:GetSchedule"]
    resources = [
      "arn:${local.partition}:scheduler:${local.region}:${local.account_id}:schedule/default/*Create",
      "arn:${local.partition}:scheduler:${local.region}:${local.account_id}:schedule/default/*Scheduled",
    ]
  }

  statement {
    sid       = "PassSchedulerRole"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.scheduler.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["scheduler.amazonaws.com"]
    }
  }

  statement {
    sid       = "SelfPermissions"
    actions   = ["lambda:AddPermission", "lambda:RemovePermission"]
    resources = [local.function_arn]
  }

  # DevOps Agent integration. GetAgentSpace only for spaces tagged dlt-integration=allowed.
  statement {
    sid       = "DevOpsAgentRead"
    actions   = ["aidevops:GetAgentSpace"]
    resources = ["arn:${local.partition}:aidevops:*:${local.account_id}:agentspace/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/dlt-integration"
      values   = ["allowed"]
    }
  }

  statement {
    sid = "DevOpsAgentWork"
    actions = [
      "aidevops:CreateAsset",
      "aidevops:CreateBacklogTask",
      "aidevops:DeleteAsset",
      "aidevops:GetBacklogTask",
      "aidevops:ListExecutions",
      "aidevops:ListJournalRecords",
      "aidevops:UpdateBacklogTask",
    ]
    resources = ["arn:${local.partition}:aidevops:*:${local.account_id}:agentspace/*"]
  }
}
