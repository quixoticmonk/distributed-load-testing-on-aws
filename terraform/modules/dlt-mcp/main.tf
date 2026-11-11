data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  partition    = data.aws_partition.current.partition
  region       = data.aws_region.current.region
  tags         = merge(var.tags, { SolutionId = var.solution_id })
  read_write   = var.access_mode == "ReadWrite"
  gateway_name = "${var.name}-mcp"
  tool_file    = "${path.module}/templates/mcp-tools-${local.read_write ? "read-write" : "read-only"}.json"
  tool_key     = "mcp/tool-schema-${local.read_write ? "read-write" : "read-only"}.json"
}

################################################################################
# Tool Lambda: translates MCP tool calls into signed DLT API calls
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

resource "aws_iam_role" "tool" {
  name_prefix        = "${substr(var.name, 0, 24)}-mcp-tool-"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "tool" {
  name              = "/aws/lambda/${var.name}-mcp-server"
  retention_in_days = var.log_retention_in_days

  tags = local.tags
}

data "aws_iam_policy_document" "tool" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.tool.arn}:*"]
  }

  statement {
    sid       = "ReadApi"
    actions   = ["execute-api:Invoke"]
    resources = ["${var.api_execution_arn}/*/GET/*"]
  }

  dynamic "statement" {
    for_each = local.read_write ? [1] : []

    content {
      sid     = "WriteApi"
      actions = ["execute-api:Invoke"]
      resources = [
        "${var.api_execution_arn}/*/DELETE/*",
        "${var.api_execution_arn}/*/POST/*",
        "${var.api_execution_arn}/*/PUT/*",
      ]
    }
  }

  dynamic "statement" {
    for_each = local.read_write ? [1] : []

    content {
      sid       = "UploadScripts"
      actions   = ["s3:PutObject"]
      resources = ["${var.scenarios_bucket_arn}/public/test-scenarios/*"]
    }
  }
}

resource "aws_iam_role_policy" "tool" {
  name   = "mcp-tool-policy"
  role   = aws_iam_role.tool.id
  policy = data.aws_iam_policy_document.tool.json
}

resource "aws_lambda_function" "tool" {
  function_name    = "${var.name}-mcp-server"
  description      = "MCP Tool Lambda Function"
  role             = aws_iam_role.tool.arn
  filename         = var.lambda_zip
  source_code_hash = filebase64sha256(var.lambda_zip)
  handler          = "index.handler"
  runtime          = "nodejs24.x"
  architectures    = ["arm64"]
  memory_size      = 512
  timeout          = 60

  environment {
    variables = merge(var.common_env, {
      API_GATEWAY_ENDPOINT  = var.api_endpoint
      SCENARIOS_BUCKET_NAME = var.scenarios_bucket_name
    })
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.tool.name
  }

  tags = local.tags

  depends_on = [aws_iam_role_policy.tool]
}

################################################################################
# Cognito: resource server + machine-to-machine client for headless agents
################################################################################

resource "aws_cognito_resource_server" "this" {
  identifier   = "dlt-mcp-gateway"
  name         = "DLT MCP Gateway Resource Server"
  user_pool_id = var.user_pool_id

  scope {
    scope_name        = "read"
    scope_description = "Read access"
  }
}

resource "aws_cognito_user_pool_client" "m2m" {
  name                                 = "${var.name}-userpool-client-m2m"
  user_pool_id                         = var.user_pool_id
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["${aws_cognito_resource_server.this.identifier}/read"]
  explicit_auth_flows                  = ["ALLOW_REFRESH_TOKEN_AUTH"]
  generate_secret                      = true
  refresh_token_validity               = 1440
  supported_identity_providers         = ["COGNITO"]

  token_validity_units {
    refresh_token = "minutes"
  }
}

################################################################################
# AgentCore Gateway (MCP endpoint, Cognito JWT inbound, IAM role outbound)
################################################################################

data "aws_iam_policy_document" "gateway_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "gateway" {
  name_prefix        = "${substr(var.name, 0, 24)}-mcp-gw-"
  assume_role_policy = data.aws_iam_policy_document.gateway_trust.json

  tags = local.tags
}

data "aws_iam_policy_document" "gateway" {
  statement {
    actions   = ["bedrock-agentcore:GetGateway"]
    resources = ["arn:${local.partition}:bedrock-agentcore:${local.region}:${local.account_id}:gateway/${local.gateway_name}*"]
  }

  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.tool.arn]
  }
}

resource "aws_iam_role_policy" "gateway" {
  name   = "agentcore-gateway-policy"
  role   = aws_iam_role.gateway.id
  policy = data.aws_iam_policy_document.gateway.json
}

resource "aws_bedrockagentcore_gateway" "this" {
  name            = local.gateway_name
  description     = "DLT MCP Server managed by AgentCore Gateway"
  authorizer_type = "CUSTOM_JWT"
  protocol_type   = "MCP"
  role_arn        = aws_iam_role.gateway.arn

  authorizer_configuration {
    custom_jwt_authorizer {
      allowed_clients = concat(var.allowed_client_ids, [aws_cognito_user_pool_client.m2m.id])
      discovery_url   = "https://cognito-idp.${local.region}.amazonaws.com/${var.user_pool_id}/.well-known/openid-configuration"
    }
  }

  tags = local.tags
}

# Tool definitions are staged in S3 rather than inlined: the provider models inline
# payloads as nested blocks, and the DLT schemas nest up to eight levels deep.
resource "aws_s3_object" "tool_schema" {
  bucket       = var.scenarios_bucket_name
  key          = local.tool_key
  source       = local.tool_file
  source_hash  = filemd5(local.tool_file)
  content_type = "application/json"

  tags = local.tags
}

resource "aws_bedrockagentcore_gateway_target" "this" {
  name               = "DltMcpToolsLambda"
  description        = "Tool provider for DLT MCP server"
  gateway_identifier = aws_bedrockagentcore_gateway.this.gateway_id

  credential_provider_configuration {
    gateway_iam_role {}
  }

  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.tool.arn

        tool_schema {
          s3 {
            uri                     = "s3://${var.scenarios_bucket_name}/${aws_s3_object.tool_schema.key}"
            bucket_owner_account_id = local.account_id
          }
        }
      }
    }
  }

  depends_on = [aws_iam_role_policy.gateway]
}
