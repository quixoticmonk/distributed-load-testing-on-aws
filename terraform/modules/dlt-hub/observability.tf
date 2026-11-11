################################################################################
# Saved CloudWatch Logs Insights queries (operational subset of upstream)
# Upstream also creates 13 billed-duration queries that only feed its anonymous
# metrics pipeline; those are not ported.
################################################################################

locals {
  orchestration_log_groups = values(module.orchestration.log_group_names)
  fn_log                   = module.orchestration.log_group_names

  saved_queries = {
    "Test Timeline" = {
      log_groups = local.orchestration_log_groups
      query      = <<-EOT
        fields @timestamp, logEvent, message, region, error
        | filter testRunId = "REPLACE_WITH_TEST_RUN_ID"
        | sort @timestamp asc
        | limit 500
      EOT
    }
    "Test Errors" = {
      log_groups = concat(local.orchestration_log_groups, [module.load_runner.log_group_name])
      query      = <<-EOT
        fields @timestamp, logEvent, message, region, taskId, error
        | filter testRunId = "REPLACE_WITH_TEST_RUN_ID" and level = "ERROR"
        | sort @timestamp asc
      EOT
    }
    "Task Failures" = {
      log_groups = [local.fn_log["task-failure-handler"]]
      query      = <<-EOT
        fields @timestamp, testId, testRunId, region, taskArn, stopCode, exitCode, stopCategory, stoppedReason
        | filter logEvent = "TASK_FAILURE_DETECTED"
        | sort @timestamp desc
        | limit 50
      EOT
    }
    "Orphan Cleanup" = {
      log_groups = [local.fn_log["orphan-cleanup"]]
      query      = <<-EOT
        fields @timestamp, logEvent, message, region, cluster, orphanCount, orphanTestIds
        | filter logEvent = "ORPHAN_DETECTED"
        | sort @timestamp desc
        | limit 50
      EOT
    }
  }
}

resource "aws_cloudwatch_query_definition" "this" {
  for_each = local.saved_queries

  name            = "DLT/${var.name}/${each.key}"
  log_group_names = each.value.log_groups
  query_string    = each.value.query
}
