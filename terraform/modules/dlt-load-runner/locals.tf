locals {
  create_vpc = var.existing_vpc_id == null

  vpc_id     = local.create_vpc ? aws_vpc.this[0].id : var.existing_vpc_id
  subnet_ids = local.create_vpc ? [for k in ["a", "b"] : aws_subnet.this[k].id] : var.existing_subnet_ids

  # The DLT Lambdas scope ECS/Logs actions on aws:ResourceTag/SolutionId; keep it on every resource.
  tags = merge(var.tags, { SolutionId = var.solution_id })

  # name => image/healthcheck start period, mirroring source/infrastructure/lib/testing-resources/ecs.ts
  task_definitions = {
    taurus = { suffix = "load-tester", start_period = 120, jvm = true }
    jmeter = { suffix = "load-tester-jmeter", start_period = 120, jvm = true }
    k6     = { suffix = "load-tester-k6", start_period = 180, jvm = false }
    locust = { suffix = "load-tester-locust", start_period = 180, jvm = false }
  }
}
