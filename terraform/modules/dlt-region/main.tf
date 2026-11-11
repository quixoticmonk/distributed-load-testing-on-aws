################################################################################
# Regional load runner (spoke)
# Replaces the upstream regional CloudFormation stack. The default provider targets
# the spoke region; aws.hub targets the hub region for registration and PassRole.
################################################################################

module "load_runner" {
  source = "../dlt-load-runner"

  name                         = var.name
  existing_subnet_ids          = var.existing_subnet_ids
  existing_vpc_id              = var.existing_vpc_id
  egress_cidr_block            = var.egress_cidr_block
  iot_endpoint                 = var.hub.iot_endpoint
  log_retention_in_days        = var.log_retention_in_days
  main_region                  = var.hub.region
  real_time_data_publisher_zip = var.real_time_data_publisher_zip
  scenarios_bucket_name        = var.hub.scenarios_bucket_name
  solution_id                  = var.solution_id
  solution_version             = var.solution_version
  subnet_cidr_blocks           = var.subnet_cidr_blocks
  tags                         = var.tags
  vpc_cidr_block               = var.vpc_cidr_block
}

# The hub's task-runner launches tasks here and must pass these roles to ECS.
data "aws_iam_policy_document" "pass_role" {
  statement {
    actions   = ["iam:PassRole"]
    resources = [module.load_runner.task_execution_role_arn, module.load_runner.task_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "hub_pass_role" {
  provider = aws.hub

  name   = "pass-role-${module.load_runner.region}"
  role   = var.hub.task_runner_role_name
  policy = data.aws_iam_policy_document.pass_role.json
}

# deploymentDate is shown in the console; pin it to first apply.
resource "terraform_data" "deployed_at" {
  input = timestamp()

  lifecycle {
    ignore_changes = [input]
  }
}

# Replaces the TestingResourcesConfigFile custom resource. The hub's API and task
# runner discover regions by scanning for region-* items in the scenarios table.
resource "aws_dynamodb_table_item" "registration" {
  provider = aws.hub

  table_name = var.hub.scenarios_table_name
  hash_key   = "testId"

  item = jsonencode({
    testId                = { S = "region-${module.load_runner.region}" }
    region                = { S = module.load_runner.region }
    ecsCloudWatchLogGroup = { S = module.load_runner.log_group_name }
    executionRoleArn      = { S = module.load_runner.task_execution_role_arn }
    subnetA               = { S = module.load_runner.subnet_ids[0] }
    subnetB               = { S = module.load_runner.subnet_ids[1] }
    taskCluster           = { S = module.load_runner.cluster_name }
    taskRoleArn           = { S = module.load_runner.task_role_arn }
    taskSecurityGroup     = { S = module.load_runner.security_group_id }
    version               = { S = var.solution_version }
    stackId               = { S = "terraform:${var.name}/${module.load_runner.region}" }
    deploymentDate        = { S = terraform_data.deployed_at.output }
  })

  # Register only once the hub can actually launch tasks here.
  depends_on = [aws_iam_role_policy.hub_pass_role]
}
