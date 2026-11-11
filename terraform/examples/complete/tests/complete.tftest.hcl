# Plan-only test with mocked providers: no AWS credentials or cost.
# Proves the full hub + spoke graph plans (no dependency cycles, every build
# artifact resolvable) in both console shapes. Resource-level checks live in each
# module's own tests/ directory.
# Requires `make build` first (real Lambda zips, web assets and JMeter bundle).

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
}

mock_provider "aws" {
  alias = "spoke"

  mock_data "aws_availability_zones" {
    defaults = { names = ["us-west-2a", "us-west-2b"] }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-west-2" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

mock_provider "random" {}

variables {
  admin_email = "admin@example.com"
}

run "cloudfront_hub_with_spoke" {
  command = plan

  assert {
    condition     = output.regions == ["us-east-1", "us-west-2"]
    error_message = "Hub and spoke regions must both be available for tests."
  }

  assert {
    condition     = output.mcp_endpoint == null
    error_message = "MCP must be off by default."
  }
}

run "headless_with_mcp_read_write" {
  command = plan

  module {
    source = "./tests/headless"
  }

  assert {
    condition     = output.console_url == null
    error_message = "Headless mode must not create console hosting."
  }

  assert {
    condition     = contains(keys(output.runtime_config), "UserPoolDomain")
    error_message = "Headless mode must still publish the runtime config for self-hosting."
  }
}
