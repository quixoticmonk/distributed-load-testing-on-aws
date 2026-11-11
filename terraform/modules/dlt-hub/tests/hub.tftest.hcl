# Mocked apply (no AWS calls, no cost). Checks the resources that replace upstream custom resources.
# Requires `make build` (artifacts under ../../build).

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b"] }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
  mock_data "aws_iot_endpoint" {
    defaults = { endpoint_address = "example-ats.iot.us-east-1.amazonaws.com" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }

  # Apply-time provider validation checks ARN syntax, so computed ARNs need real shapes.
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/mock" }
  }
  mock_resource "aws_lambda_function" {
    defaults = { arn = "arn:aws:lambda:us-east-1:111111111111:function:mock" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-1:111111111111:log-group:mock" }
  }
  mock_resource "aws_cloudwatch_event_rule" {
    defaults = { arn = "arn:aws:events:us-east-1:111111111111:rule/mock" }
  }
  mock_resource "aws_sfn_state_machine" {
    defaults = { arn = "arn:aws:states:us-east-1:111111111111:stateMachine:mock" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::mock", bucket_regional_domain_name = "mock.s3.us-east-1.amazonaws.com" }
  }
  mock_resource "aws_dynamodb_table" {
    defaults = { arn = "arn:aws:dynamodb:us-east-1:111111111111:table/mock" }
  }
  mock_resource "aws_cognito_user_pool" {
    defaults = { arn = "arn:aws:cognito-idp:us-east-1:111111111111:userpool/us-east-1_mock", endpoint = "cognito-idp.us-east-1.amazonaws.com/us-east-1_mock" }
  }
  mock_resource "aws_api_gateway_rest_api" {
    defaults = { execution_arn = "arn:aws:execute-api:us-east-1:111111111111:mockapi" }
  }
  mock_resource "aws_cloudfront_distribution" {
    defaults = { arn = "arn:aws:cloudfront::111111111111:distribution/MOCK", domain_name = "dmock.cloudfront.net" }
  }
  mock_resource "aws_cloudformation_stack" {
    defaults = { id = "arn:aws:cloudformation:us-east-1:111111111111:stack/dlt-metadata/mock" }
  }
  mock_resource "aws_api_gateway_stage" {
    defaults = { invoke_url = "https://mockapi.execute-api.us-east-1.amazonaws.com/prod" }
  }
  mock_resource "aws_ecs_task_definition" {
    defaults = { arn = "arn:aws:ecs:us-east-1:111111111111:task-definition/mock:1" }
  }
  mock_resource "aws_bedrockagentcore_gateway" {
    defaults = { gateway_url = "https://mock.gateway.bedrock-agentcore.us-east-1.amazonaws.com/mcp" }
  }
}

mock_provider "random" {
  mock_resource "random_uuid" {
    defaults = { result = "00000000-0000-4000-8000-000000000000" }
  }
}

variables {
  name          = "dlt"
  admin_email   = "admin@example.com"
  admin_name    = "dlt-admin"
  artifacts_dir = "../../build"
}

run "replaces_custom_resources" {
  command = apply

  # TestingResourcesConfigFile -> DynamoDB item
  assert {
    condition     = jsondecode(aws_dynamodb_table_item.hub_region.item).testId.S == "region-us-east-1"
    error_message = "Hub must register itself as region-us-east-1."
  }

  assert {
    condition     = keys(jsondecode(aws_dynamodb_table_item.hub_region.item).nativeTaskDefinitions.M) == ["jmeter", "k6", "locust"]
    error_message = "Hub registration must carry jmeter, k6 and locust task definitions."
  }

  # Delete-time custom resources -> aws_lambda_invocation (actions have no destroy events)
  assert {
    condition     = aws_lambda_invocation.cleanup_test_scenarios.lifecycle_scope == "CRUD"
    error_message = "Schedule cleanup must run on destroy (lifecycle_scope CRUD)."
  }

  assert {
    condition     = aws_lambda_invocation.detach_iot_policy.lifecycle_scope == "CRUD"
    error_message = "IoT policy detach must run on destroy (lifecycle_scope CRUD)."
  }

  # The API reads these from CloudFormation at runtime (/stack-info, /regions).
  assert {
    condition = alltrue([
      for k in ["SolutionTemplate", "SolutionUUID", "RegionalCFTemplate"] :
      contains(keys(jsondecode(aws_cloudformation_stack.metadata.template_body).Outputs), k)
    ])
    error_message = "Metadata stack must expose SolutionTemplate, SolutionUUID and RegionalCFTemplate."
  }

  assert {
    condition     = jsondecode(aws_cloudformation_stack.metadata.template_body).Outputs.RegionalCFTemplate.Export.Name == "dlt-metadata-RegionalCFTemplate"
    error_message = "Export name must be <STACK_NAME>-RegionalCFTemplate; the API looks it up by that name."
  }

  assert {
    condition     = aws_cloudformation_stack.metadata.tags["SolutionVersion"] == var.solution_version
    error_message = "/stack-info reads the version from the SolutionVersion tag."
  }

  assert {
    condition     = output.runtime_config.UserPoolDomain == "dlt-00000000-0000-4000-8000-000000000000.auth.us-east-1.amazoncognito.com"
    error_message = "Cognito domain must be derived from the deployment UUID."
  }
}

run "mcp_adds_endpoint_output" {
  command = apply

  variables {
    deploy_mcp_server = true
  }

  assert {
    condition     = contains(keys(jsondecode(aws_cloudformation_stack.metadata.template_body).Outputs), "McpEndpoint")
    error_message = "With MCP enabled, /stack-info must find the McpEndpoint output."
  }
}
