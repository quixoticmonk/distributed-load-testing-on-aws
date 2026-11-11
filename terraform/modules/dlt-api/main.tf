data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  tags          = merge(var.tags, { SolutionId = var.solution_id })
  function_name = "${var.name}-api-services"
  function_arn  = "arn:${local.partition}:lambda:${local.region}:${local.account_id}:function:${local.function_name}"
}

################################################################################
# API Lambda (api-services)
################################################################################

resource "aws_cloudwatch_log_group" "api_lambda" {
  name              = "/aws/lambda/${local.function_name}"
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

resource "aws_iam_role" "api_lambda" {
  name_prefix        = "${substr(var.name, 0, 24)}-api-"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json

  tags = local.tags
}

resource "aws_iam_role_policy" "api_lambda" {
  name   = "api-services-policy"
  role   = aws_iam_role.api_lambda.id
  policy = data.aws_iam_policy_document.api_lambda.json
}

resource "aws_lambda_function" "api" {
  function_name    = local.function_name
  description      = "API microservices for creating, updating, listing and deleting test scenarios"
  role             = aws_iam_role.api_lambda.arn
  filename         = var.lambda_zip
  source_code_hash = filebase64sha256(var.lambda_zip)
  handler          = "index.handler"
  runtime          = "nodejs24.x"
  architectures    = ["arm64"]
  timeout          = 120

  environment {
    variables = merge(var.common_env, {
      AGENT_SPACES_TABLE     = var.agent_spaces_table_name
      HISTORY_TABLE          = var.history_table_name
      HISTORY_TABLE_GSI_NAME = var.history_table_gsi_name
      INVESTIGATIONS_TABLE   = var.investigations_table_name
      MIN_COMPATIBLE_VERSION = var.min_compatible_version
      SCENARIOS_BUCKET       = var.scenarios_bucket_name
      SCENARIOS_TABLE        = var.scenarios_table_name
      SCHEDULER_ROLE_ARN     = aws_iam_role.scheduler.arn
      STACK_ID               = var.metadata_stack_id
      STACK_NAME             = var.metadata_stack_name
      STATE_MACHINE_ARN      = var.state_machine_arn
      TASK_CANCELER_ARN      = var.task_canceler_arn
    })
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.api_lambda.name
  }

  tags = local.tags

  depends_on = [aws_iam_role_policy.api_lambda]
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*"
}

################################################################################
# EventBridge Scheduler role (scheduled tests invoke the API Lambda)
################################################################################

data "aws_iam_policy_document" "scheduler_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name_prefix        = "${substr(var.name, 0, 24)}-sched-"
  assume_role_policy = data.aws_iam_policy_document.scheduler_trust.json

  tags = local.tags
}

data "aws_iam_policy_document" "scheduler" {
  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [local.function_arn]
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name   = "invoke-api-lambda"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler.json
}

################################################################################
# REST API, deployment, stage
################################################################################

resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.name}-api"
  description = "Distributed Load Testing API - version ${var.common_env["VERSION"]}"
  body        = jsonencode(local.openapi)

  endpoint_configuration {
    types = [var.endpoint_type]
  }

  tags = local.tags
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  description = "Distributed Load Testing API - version ${var.common_env["VERSION"]}"

  triggers = {
    redeployment = sha1(aws_api_gateway_rest_api.this.body)
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "access" {
  name              = "/dlt/${var.name}/api-access"
  retention_in_days = var.log_retention_in_days

  tags = local.tags
}

resource "aws_api_gateway_stage" "prod" {
  # The console, Cognito role policy and MCP tool Lambda all assume the stage is "prod".
  stage_name           = "prod"
  rest_api_id          = aws_api_gateway_rest_api.this.id
  deployment_id        = aws_api_gateway_deployment.this.id
  xray_tracing_enabled = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
    format = jsonencode({
      extendedRequestId = "$context.extendedRequestId"
      ip                = "$context.identity.sourceIp"
      caller            = "$context.identity.caller"
      user              = "$context.identity.user"
      userAgent         = "$context.identity.userAgent"
      requestTime       = "$context.requestTime"
      httpMethod        = "$context.httpMethod"
      resourcePath      = "$context.resourcePath"
      status            = "$context.status"
      protocol          = "$context.protocol"
      responseLength    = "$context.responseLength"
    })
  }

  tags = local.tags

  depends_on = [aws_api_gateway_account.this]
}

resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  method_path = "*/*"

  settings {
    data_trace_enabled = false
    logging_level      = "INFO"
    metrics_enabled    = false
  }

  depends_on = [aws_api_gateway_account.this]
}

################################################################################
# Account-wide API Gateway CloudWatch role (optional)
# This is an account+region singleton. Upstream sets it twice in the same stack;
# in a shared account it belongs to the landing zone, not to this product.
################################################################################

data "aws_iam_policy_document" "apigw_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apigw_cloudwatch" {
  count = var.manage_api_gateway_account ? 1 : 0

  name_prefix        = "${substr(var.name, 0, 24)}-apigw-cw-"
  assume_role_policy = data.aws_iam_policy_document.apigw_trust.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "apigw_cloudwatch" {
  count = var.manage_api_gateway_account ? 1 : 0

  role       = aws_iam_role.apigw_cloudwatch[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "this" {
  count = var.manage_api_gateway_account ? 1 : 0

  cloudwatch_role_arn = aws_iam_role.apigw_cloudwatch[0].arn

  depends_on = [aws_iam_role_policy_attachment.apigw_cloudwatch]
}
