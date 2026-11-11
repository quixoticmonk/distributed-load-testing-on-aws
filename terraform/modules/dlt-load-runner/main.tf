data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

################################################################################
# Network (only when no existing VPC is supplied)
# Mirrors the upstream DLTVpc construct: two public subnets behind an IGW.
################################################################################

resource "aws_vpc" "this" {
  count = local.create_vpc ? 1 : 0

  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.tags, { Name = var.name })
}

# Strip all rules from the VPC's default security group (nothing should use it).
resource "aws_default_security_group" "this" {
  count = local.create_vpc ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  tags = merge(local.tags, { Name = "${var.name}-default-deny" })
}

resource "aws_subnet" "this" {
  for_each = local.create_vpc ? { a = 0, b = 1 } : {}

  availability_zone = data.aws_availability_zones.available.names[each.value]
  cidr_block        = var.subnet_cidr_blocks[each.value]
  vpc_id            = aws_vpc.this[0].id

  tags = merge(local.tags, { Name = "${var.name}-${each.key}" })
}

resource "aws_internet_gateway" "this" {
  count = local.create_vpc ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  tags = merge(local.tags, { Name = var.name })
}

resource "aws_route_table" "this" {
  count = local.create_vpc ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[0].id
  }

  tags = merge(local.tags, { Name = var.name })
}

resource "aws_route_table_association" "this" {
  for_each = aws_subnet.this

  route_table_id = aws_route_table.this[0].id
  subnet_id      = each.value.id
}

################################################################################
# Load generator security group (egress only)
################################################################################

resource "aws_security_group" "tasks" {
  name_prefix = "${var.name}-tasks-"
  description = "DLTS Tasks Security Group"
  vpc_id      = local.vpc_id

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "tasks" {
  security_group_id = aws_security_group.tasks.id

  cidr_ipv4   = var.egress_cidr_block
  description = "Allow tasks to call out to external resources"
  ip_protocol = "-1"

  tags = local.tags
}

################################################################################
# ECS cluster, roles, log group
################################################################################

resource "aws_ecs_cluster" "this" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "tasks" {
  name_prefix       = "/dlt/${var.name}/ecs-"
  retention_in_days = var.log_retention_in_days

  tags = local.tags
}

data "aws_iam_policy_document" "ecs_tasks_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name_prefix        = "${substr(var.name, 0, 24)}-ecs-exec-"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json

  tags = local.tags
}

data "aws_iam_policy_document" "task_execution" {
  # ecr:GetAuthorizationToken has no resource-level permissions.
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:ecr:*:*:repository/*"]
  }

  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.tasks.arn}:*"]
  }
}

resource "aws_iam_role_policy" "task_execution" {
  name   = "ECSTaskExecutionPolicy"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution.json
}

resource "aws_iam_role" "task" {
  name_prefix        = "${substr(var.name, 0, 24)}-ecs-task-"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json

  tags = local.tags
}

data "aws_iam_policy_document" "task" {
  statement {
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${var.scenarios_bucket_name}",
      "arn:${data.aws_partition.current.partition}:s3:::${var.scenarios_bucket_name}/*",
    ]
  }
}

resource "aws_iam_role_policy" "task" {
  name   = "ScenariosS3Policy"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task.json
}

resource "aws_cloudwatch_metric_alarm" "metric_filter_count" {
  alarm_name          = "${var.name}-${data.aws_region.current.region}-MetricFilterCount-Alarm"
  alarm_description   = "Alarm when metric filter count approaches the limit of 100"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "MetricFilterCount"
  namespace           = "distributed-load-testing"
  period              = 300
  statistic           = "Maximum"
  threshold           = 90
  treat_missing_data  = "notBreaching"

  dimensions = {
    LogGroupName = aws_cloudwatch_log_group.tasks.name
  }

  tags = local.tags
}

################################################################################
# Task definitions (hub only)
################################################################################

resource "aws_ecs_task_definition" "this" {
  for_each = var.create_task_definitions ? local.task_definitions : {}

  family                   = "${var.name}-${each.value.suffix}"
  cpu                      = "2048"
  memory                   = "4096"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name        = "${var.name}-${each.value.suffix}"
      image       = var.load_tester_images[each.key]
      essential   = true
      memory      = 4096
      stopTimeout = 120
      environment = each.value.jvm ? [
        { name = "JVM_ARGS", value = "-Xms1g -Xmx3g -XX:+ExitOnOutOfMemoryError -XX:-HeapDumpOnOutOfMemoryError" },
      ] : []
      healthCheck = {
        command     = ["CMD-SHELL", "test -f /tmp/health_ready || exit 1"]
        interval    = 5
        retries     = 10
        startPeriod = each.value.start_period
        timeout     = 5
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.tasks.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "load-testing"
        }
      }
    },
  ])

  tags = local.tags

  lifecycle {
    precondition {
      condition     = contains(keys(var.load_tester_images), each.key)
      error_message = "load_tester_images must contain an image for '${each.key}'."
    }
  }
}
