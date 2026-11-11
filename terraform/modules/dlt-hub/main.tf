################################################################################
# Distributed Load Testing hub (composition)
# Wires the per-concern modules together. Each module is usable on its own; this
# file is the only place that knows how they connect.
################################################################################

module "storage" {
  source = "../dlt-storage"

  name                         = var.name
  access_log_retention_in_days = var.access_log_retention_in_days
  console_origins              = local.console_urls
  enable_deletion_protection   = var.enable_deletion_protection
  jmeter_bundle_path           = "${var.artifacts_dir}/jmeter/jmeter-bundle.tgz"
  kms_key_arn                  = var.kms_key_arn
  solution_id                  = var.solution_id
  tags                         = var.tags
}

module "load_runner" {
  source = "../dlt-load-runner"

  name                         = var.name
  create_task_definitions      = true
  egress_cidr_block            = var.egress_cidr_block
  existing_subnet_ids          = var.existing_subnet_ids
  existing_vpc_id              = var.existing_vpc_id
  iot_endpoint                 = data.aws_iot_endpoint.this.endpoint_address
  load_tester_images           = local.load_tester_images
  log_retention_in_days        = var.log_retention_in_days
  main_region                  = local.region
  real_time_data_publisher_zip = local.lambda_zip["real-time-data-publisher"]
  scenarios_bucket_name        = module.storage.scenarios_bucket_name
  solution_id                  = var.solution_id
  solution_version             = var.solution_version
  subnet_cidr_blocks           = var.subnet_cidr_blocks
  tags                         = var.tags
  vpc_cidr_block               = var.vpc_cidr_block
}

module "orchestration" {
  source = "../dlt-orchestration"

  name                        = var.name
  common_env                  = local.common_env
  ecs_task_execution_role_arn = module.load_runner.task_execution_role_arn
  ecs_task_role_arn           = module.load_runner.task_role_arn
  history_table_arn           = module.storage.history_table_arn
  history_table_name          = module.storage.history_table_name
  lambda_zips                 = local.orchestration_zips
  log_retention_in_days       = var.log_retention_in_days
  scenarios_bucket_arn        = module.storage.scenarios_bucket_arn
  scenarios_bucket_name       = module.storage.scenarios_bucket_name
  scenarios_table_arn         = module.storage.scenarios_table_arn
  scenarios_table_name        = module.storage.scenarios_table_name
  solution_id                 = var.solution_id
  tags                        = var.tags
}

module "api" {
  source = "../dlt-api"

  name                        = var.name
  agent_spaces_table_arn      = module.storage.agent_spaces_table_arn
  agent_spaces_table_name     = module.storage.agent_spaces_table_name
  common_env                  = local.common_env
  ecs_task_execution_role_arn = module.load_runner.task_execution_role_arn
  ecs_task_role_arn           = module.load_runner.task_role_arn
  endpoint_type               = var.api_endpoint_type
  history_table_arn           = module.storage.history_table_arn
  history_table_gsi_name      = module.storage.history_table_gsi_name
  history_table_name          = module.storage.history_table_name
  investigations_table_arn    = module.storage.investigations_table_arn
  investigations_table_name   = module.storage.investigations_table_name
  lambda_zip                  = local.lambda_zip["api-services"]
  log_retention_in_days       = var.log_retention_in_days
  manage_api_gateway_account  = var.manage_api_gateway_account
  metadata_stack_id           = aws_cloudformation_stack.metadata.id
  metadata_stack_name         = aws_cloudformation_stack.metadata.name
  scenarios_bucket_arn        = module.storage.scenarios_bucket_arn
  scenarios_bucket_name       = module.storage.scenarios_bucket_name
  scenarios_table_arn         = module.storage.scenarios_table_arn
  scenarios_table_name        = module.storage.scenarios_table_name
  solution_id                 = var.solution_id
  state_machine_arn           = module.orchestration.state_machine_arn
  tags                        = var.tags
  task_canceler_arn           = module.orchestration.task_canceler_arn
}

module "auth" {
  source = "../dlt-auth"

  name                       = var.name
  additional_callback_urls   = var.oauth_additional_callback_urls
  admin_email                = var.admin_email
  admin_name                 = var.admin_name
  api_execution_arn          = module.api.execution_arn
  api_stage_name             = module.api.stage_name
  console_urls               = local.console_urls
  domain_prefix              = local.cognito_domain_prefix
  enable_deletion_protection = var.enable_deletion_protection
  log_retention_in_days      = var.log_retention_in_days
  scenarios_bucket_arn       = module.storage.scenarios_bucket_arn
  solution_id                = var.solution_id
  tags                       = var.tags
  user_pool_tier             = var.user_pool_tier
}

module "console" {
  source = "../dlt-console"
  count  = local.cloudfront ? 1 : 0

  name                             = var.name
  cognito_domain_host              = local.cognito_domain_host
  logs_bucket_id                   = module.storage.logs_bucket_id
  logs_bucket_regional_domain_name = module.storage.logs_bucket_regional_domain_name
  runtime_config                   = local.runtime_config
  solution_id                      = var.solution_id
  tags                             = var.tags
  web_acl_arn                      = var.console_web_acl_arn
  webui_dir                        = "${var.artifacts_dir}/webui"
}

module "mcp" {
  source = "../dlt-mcp"
  count  = var.deploy_mcp_server ? 1 : 0

  name                  = var.name
  access_mode           = var.mcp_access_mode
  allowed_client_ids    = [module.auth.console_client_id]
  api_endpoint          = module.api.api_endpoint
  api_execution_arn     = module.api.execution_arn
  common_env            = local.common_env
  lambda_zip            = local.lambda_zip["mcp-server"]
  log_retention_in_days = var.log_retention_in_days
  scenarios_bucket_arn  = module.storage.scenarios_bucket_arn
  scenarios_bucket_name = module.storage.scenarios_bucket_name
  solution_id           = var.solution_id
  tags                  = var.tags
  user_pool_id          = module.auth.user_pool_id
}

################################################################################
# Hub region registration (replaces the hub TestingResourcesConfigFile custom resource)
################################################################################

resource "terraform_data" "deployed_at" {
  input = timestamp()

  lifecycle {
    ignore_changes = [input]
  }
}

resource "aws_dynamodb_table_item" "hub_region" {
  table_name = module.storage.scenarios_table_name
  hash_key   = "testId"

  item = jsonencode({
    testId                = { S = "region-${local.region}" }
    region                = { S = local.region }
    ecsCloudWatchLogGroup = { S = module.load_runner.log_group_name }
    executionRoleArn      = { S = module.load_runner.task_execution_role_arn }
    subnetA               = { S = module.load_runner.subnet_ids[0] }
    subnetB               = { S = module.load_runner.subnet_ids[1] }
    taskCluster           = { S = module.load_runner.cluster_name }
    taskDefinition        = { S = module.load_runner.task_definition_arns["taurus"] }
    taskRoleArn           = { S = module.load_runner.task_role_arn }
    taskSecurityGroup     = { S = module.load_runner.security_group_id }
    version               = { S = var.solution_version }
    stackId               = { S = aws_cloudformation_stack.metadata.id }
    deploymentDate        = { S = terraform_data.deployed_at.output }
    nativeTaskDefinitions = {
      M = {
        jmeter = { S = module.load_runner.task_definition_arns["jmeter"] }
        k6     = { S = module.load_runner.task_definition_arns["k6"] }
        locust = { S = module.load_runner.task_definition_arns["locust"] }
      }
    }
  })
}
