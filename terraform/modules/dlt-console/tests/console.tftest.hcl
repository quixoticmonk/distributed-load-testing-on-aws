# Plan-only, mocked. Checks the CSP (replaces the UpdateCsp custom resource) and
# that aws-exports.json is never uploaded from the build directory.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

variables {
  name                             = "dlt"
  cognito_domain_host              = "dlt-test.auth.us-east-1.amazoncognito.com"
  logs_bucket_id                   = "logs"
  logs_bucket_regional_domain_name = "logs.s3.us-east-1.amazonaws.com"
  runtime_config                   = { ApiEndpoint = "https://example.execute-api.us-east-1.amazonaws.com/prod" }
  webui_dir                        = "../../build/webui"
}

run "csp_includes_cognito_origin" {
  command = plan

  assert {
    condition = alltrue([
      for d in ["default-src", "script-src", "connect-src", "form-action"] :
      length(regexall("${d} [^;]*https://dlt-test\\.auth\\.us-east-1\\.amazoncognito\\.com", aws_cloudfront_response_headers_policy.this.security_headers_config[0].content_security_policy[0].content_security_policy)) == 1
    ])
    error_message = "Cognito origin must be in default-src, script-src, connect-src and form-action."
  }

  assert {
    condition     = !contains(keys(aws_s3_object.webui), "aws-exports.json")
    error_message = "aws-exports.json must come from runtime_config, not the build directory."
  }

  assert {
    condition     = aws_s3_object.webui["index.html"].cache_control == "no-cache"
    error_message = "index.html must not be cached."
  }
}
