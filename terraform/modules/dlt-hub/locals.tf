data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

# Replaces the GetIotEndpoint custom resource.
data "aws_iot_endpoint" "this" {
  endpoint_type = "iot:Data-ATS"
}

# Replaces the UUID custom resource. It names the Cognito domain, so it must stay
# stable for the life of the deployment.
resource "random_uuid" "this" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  uuid = random_uuid.this.result
  tags = merge(var.tags, { SolutionId = var.solution_id })

  # Explicit list so a missing build fails with "no file exists" rather than an index error.
  lambda_zip = {
    for k in [
      "api-services", "mcp-server", "metrics-emitter", "ops-adapter", "orphan-cleanup",
      "real-time-data-publisher", "regional-sync", "results-parser", "sfn-failure-handler",
      "stabilization-checker", "start-command", "task-canceler", "task-failure-handler",
      "task-runner", "task-status-checker", "test-cleanup", "test-metadata-updater",
    ] : k => "${var.artifacts_dir}/lambda/${k}.zip"
  }
  orchestration_zips = { for k, v in local.lambda_zip : k => v if !contains(["api-services", "mcp-server", "ops-adapter", "real-time-data-publisher"], k) }

  # Public AWS Solutions images unless overridden per framework.
  public_image_repo = {
    taurus = "distributed-load-testing-on-aws-load-tester"
    jmeter = "distributed-load-testing-on-aws-load-tester-jmeter"
    k6     = "distributed-load-testing-on-aws-load-tester-k6"
    locust = "distributed-load-testing-on-aws-load-tester-locust"
  }
  load_tester_images = {
    for k, repo in local.public_image_repo :
    k => lookup(var.load_tester_images, k, "public.ecr.aws/aws-solutions/${repo}:${var.load_tester_image_tag}")
  }

  # The hosted domain is deterministic from the UUID, so the console CSP can include it
  # up front instead of patching the policy after deploy (UpdateCsp custom resource).
  cognito_domain_prefix = "dlt-${local.uuid}"
  cognito_domain_host   = "${local.cognito_domain_prefix}.${local.partition == "aws-us-gov" ? "auth-fips" : "auth"}.${local.region}.amazoncognito.com"

  cloudfront   = var.console_mode == "cloudfront"
  console_urls = local.cloudfront ? [module.console[0].console_url] : var.external_console_urls

  common_env = {
    AWS_ACCOUNT_ID = local.account_id
    METRIC_URL     = var.solution_metrics_url
    SOLUTION_ID    = var.solution_id
    UUID           = local.uuid
    VERSION        = var.solution_version
  }

  # Contents of /aws-exports.json, which the console fetches at startup.
  runtime_config = {
    ApiEndpoint           = module.api.api_endpoint
    IdentityPoolId        = module.auth.identity_pool_id
    IoTEndpoint           = data.aws_iot_endpoint.this.endpoint_address
    IoTPolicy             = module.auth.iot_policy_name
    PoolClientId          = module.auth.console_client_id
    UserFilesBucket       = module.storage.scenarios_bucket_name
    UserFilesBucketRegion = local.region
    UserPoolDomain        = local.cognito_domain_host
    UserPoolId            = module.auth.user_pool_id
  }
}
