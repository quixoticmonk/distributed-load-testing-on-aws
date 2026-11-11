################################################################################
# Lifecycle hooks (replacing CloudFormation custom resources)
#
# Upstream custom resource   -> Terraform replacement
#   UUID                     -> random_uuid
#   GetIotEndpoint           -> data.aws_iot_endpoint
#   TestingResourcesConfig   -> aws_dynamodb_table_item (hub + each dlt-region)
#   ConsoleConfig/aws-exports-> aws_s3_object (dlt-console)
#   BucketDeployment         -> aws_s3_object for_each + CloudFront invalidation action
#   UpdateCsp                -> CSP computed up front (dlt-console)
#   CognitoUICustomization   -> aws_cognito_user_pool_ui_customization
#   CopyJMeterBundle         -> aws_s3_object (dlt-storage)
#   PutRegionalTemplate      -> not needed; regions use the dlt-region module
#   Metric (anonymous usage) -> dropped
#   V3toV4BackCompat         -> dropped; only applies to in-place upgrades from v3 stacks
#   BackfillTestRunCounts    -> Terraform action (after_create/after_update)
#   CleanUpTestScenarios     -> aws_lambda_invocation, lifecycle_scope CRUD (destroy)
#   DetachIotPolicy          -> aws_lambda_invocation, lifecycle_scope CRUD (destroy)
#
# Terraform actions only fire on create/update events, so delete-time work uses
# aws_lambda_invocation, which re-invokes with tf.action = "delete" on destroy.
################################################################################

resource "aws_cloudwatch_log_group" "ops_adapter" {
  name              = "/aws/lambda/${var.name}-ops-adapter"
  retention_in_days = var.log_retention_in_days

  tags = local.tags
}

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ops_adapter" {
  name_prefix        = "${substr(var.name, 0, 24)}-ops-"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json

  tags = local.tags
}

data "aws_iam_policy_document" "ops_adapter" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.ops_adapter.arn}:*"]
  }

  statement {
    sid       = "ScenariosTable"
    actions   = ["dynamodb:Scan", "dynamodb:UpdateItem"]
    resources = [module.storage.scenarios_table_arn]
  }

  statement {
    sid       = "HistoryTable"
    actions   = ["dynamodb:Query"]
    resources = [module.storage.history_table_arn]
  }

  statement {
    sid     = "DeleteTestSchedules"
    actions = ["scheduler:DeleteSchedule"]
    resources = [
      "arn:${local.partition}:scheduler:${local.region}:${local.account_id}:schedule/default/*Create",
      "arn:${local.partition}:scheduler:${local.region}:${local.account_id}:schedule/default/*Scheduled",
    ]
  }

  statement {
    sid       = "IotListTargets"
    actions   = ["iot:ListTargetsForPolicy"]
    resources = ["arn:${local.partition}:iot:${local.region}:${local.account_id}:policy/${module.auth.iot_policy_name}"]
  }

  # DetachPrincipalPolicy does not support resource-level permissions.
  statement {
    sid       = "IotDetach"
    actions   = ["iot:DetachPrincipalPolicy"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ops_adapter" {
  name   = "ops-adapter-policy"
  role   = aws_iam_role.ops_adapter.id
  policy = data.aws_iam_policy_document.ops_adapter.json
}

resource "aws_lambda_function" "ops_adapter" {
  function_name    = "${var.name}-ops-adapter"
  description      = "Terraform lifecycle hooks for DLT (cleanup, IoT detach, backfill)"
  role             = aws_iam_role.ops_adapter.arn
  filename         = local.lambda_zip["ops-adapter"]
  source_code_hash = filebase64sha256(local.lambda_zip["ops-adapter"])
  handler          = "index.handler"
  runtime          = "nodejs24.x"
  architectures    = ["arm64"]
  timeout          = 300

  environment {
    variables = merge(local.common_env, {
      DDB_TABLE     = module.storage.scenarios_table_name
      HISTORY_TABLE = module.storage.history_table_name
      MAIN_REGION   = local.region
    })
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.ops_adapter.name
  }

  tags = local.tags
}

# --- Create/update hook: Terraform action -------------------------------------

action "aws_lambda_invoke" "backfill_test_run_counts" {
  config {
    function_name = aws_lambda_function.ops_adapter.function_name
    payload       = jsonencode({ operation = "backfill-test-run-counts" })
  }
}

# Fires on first apply and whenever the solution version changes (upgrade path).
resource "terraform_data" "backfill_trigger" {
  input = var.solution_version

  lifecycle {
    action_trigger {
      events  = [after_create, after_update]
      actions = [action.aws_lambda_invoke.backfill_test_run_counts]
    }
  }

  depends_on = [aws_iam_role_policy.ops_adapter]
}

# --- Destroy hooks: aws_lambda_invocation with CRUD scope ----------------------
# Destroy order is the reverse of dependencies, so each invocation runs its
# "delete" call before the resources it references are removed.

# Remove EventBridge Scheduler schedules that scheduled tests created outside Terraform.
resource "aws_lambda_invocation" "cleanup_test_scenarios" {
  function_name   = aws_lambda_function.ops_adapter.function_name
  lifecycle_scope = "CRUD"
  input           = jsonencode({ operation = "cleanup-test-scenarios" })

  depends_on = [aws_iam_role_policy.ops_adapter, module.api]
}

# Detach Cognito identities from the IoT policy so aws_iot_policy can be deleted.
resource "aws_lambda_invocation" "detach_iot_policy" {
  function_name   = aws_lambda_function.ops_adapter.function_name
  lifecycle_scope = "CRUD"
  input = jsonencode({
    operation     = "detach-iot-policy"
    iotPolicyName = module.auth.iot_policy_name
  })

  depends_on = [aws_iam_role_policy.ops_adapter]
}
