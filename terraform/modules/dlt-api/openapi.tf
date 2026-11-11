################################################################################
# REST API definition
# Route table mirrors source/infrastructure/lib/front-end/api.ts. Every route is an
# IAM-authorized Lambda proxy plus an unauthenticated CORS preflight (MOCK).
################################################################################

locals {
  # path => methods ("ANY" becomes x-amazon-apigateway-any-method)
  routes = {
    "/"                                                                                  = []
    "/agent-spaces"                                                                      = ["GET", "POST"]
    "/agent-spaces/test-connection"                                                      = ["POST"]
    "/agent-spaces/{id}"                                                                 = ["PUT", "DELETE"]
    "/regions"                                                                           = ["ANY"]
    "/scenarios"                                                                         = ["ANY"]
    "/scenarios/{testId}"                                                                = ["ANY"]
    "/scenarios/{testId}/baseline"                                                       = ["GET", "PUT", "DELETE"]
    "/scenarios/{testId}/testruns"                                                       = ["ANY"]
    "/scenarios/{testId}/testruns/{testRunId}"                                           = ["ANY"]
    "/scenarios/{testId}/testruns/{testRunId}/investigations"                            = ["GET", "POST"]
    "/scenarios/{testId}/testruns/{testRunId}/investigations/{investigationId}"          = ["PUT", "DELETE"]
    "/scenarios/{testId}/testruns/{testRunId}/investigations/{investigationId}/findings" = ["GET"]
    "/scenarios/{testId}/testruns/{testRunId}/investigations/{investigationId}/status"   = ["GET"]
    "/stack-info"                                                                        = ["ANY"]
    "/tasks"                                                                             = ["ANY"]
    "/vCPUDetails"                                                                       = ["ANY"]
  }

  cors_headers = {
    "Access-Control-Allow-Headers" = "'Authorization,Content-Type,X-Amz-Date,X-Amz-Security-Token,X-Api-Key'"
    "Access-Control-Allow-Methods" = "'DELETE,GET,HEAD,OPTIONS,PATCH,POST,PUT'"
    "Access-Control-Allow-Origin"  = "'*'"
  }

  # Computed ARN, not a resource reference: the API Lambda's env depends (via the
  # metadata stack) on the MCP gateway, which depends on this API's stage URL.
  lambda_invoke_uri = "arn:${local.partition}:apigateway:${local.region}:lambda:path/2015-03-31/functions/${local.function_arn}/invocations"

  path_params = {
    for p in keys(local.routes) : p => [
      for name in regexall("\\{([A-Za-z]+)\\}", p) : {
        name     = name[0]
        in       = "path"
        required = true
        schema   = { type = "string" }
      }
    ]
  }

  proxy_operation = {
    security                                = [{ sigv4 = [] }]
    "x-amazon-apigateway-request-validator" = "all"
    responses = {
      "200" = {
        description = "200 response"
        content     = { "application/json" = { schema = { "$ref" = "#/components/schemas/Empty" } } }
      }
    }
    "x-amazon-apigateway-integration" = {
      type                = "aws_proxy"
      httpMethod          = "POST"
      uri                 = local.lambda_invoke_uri
      passthroughBehavior = "when_no_match"
      contentHandling     = "CONVERT_TO_TEXT"
    }
  }

  cors_operation = {
    responses = {
      "200" = {
        description = "CORS preflight"
        headers     = { for h in keys(local.cors_headers) : h => { schema = { type = "string" } } }
      }
    }
    "x-amazon-apigateway-integration" = {
      type             = "mock"
      requestTemplates = { "application/json" = "{ statusCode: 200 }" }
      responses = {
        default = {
          statusCode         = "200"
          responseParameters = { for h, v in local.cors_headers : "method.response.header.${h}" => v }
        }
      }
    }
  }

  openapi = {
    openapi = "3.0.1"
    info = {
      title   = "${var.name}-api"
      version = var.common_env["VERSION"]
    }
    paths = {
      for p, methods in local.routes : p => merge(
        { options = merge(local.cors_operation, length(local.path_params[p]) > 0 ? { parameters = local.path_params[p] } : {}) },
        {
          for m in methods :
          (m == "ANY" ? "x-amazon-apigateway-any-method" : lower(m)) => merge(
            local.proxy_operation,
            length(local.path_params[p]) > 0 ? { parameters = local.path_params[p] } : {},
          )
        },
      )
    }
    components = {
      schemas = {
        Empty = { title = "Empty Schema", type = "object" }
      }
      securitySchemes = {
        sigv4 = {
          type                           = "apiKey"
          name                           = "Authorization"
          in                             = "header"
          "x-amazon-apigateway-authtype" = "awsSigv4"
        }
      }
    }
    "x-amazon-apigateway-request-validators" = {
      all = { validateRequestBody = true, validateRequestParameters = true }
    }
  }
}
