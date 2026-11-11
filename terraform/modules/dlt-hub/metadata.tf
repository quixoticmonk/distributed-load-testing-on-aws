################################################################################
# CloudFormation metadata shim
#
# The DLT API reads CloudFormation at runtime even though it manages nothing there:
#   GET /stack-info -> DescribeStacks(STACK_ID): SolutionVersion tag, SolutionTemplate,
#                      SolutionUUID and McpEndpoint outputs (the console calls it on load)
#   GET /regions    -> ListExports: "<STACK_NAME>-RegionalCFTemplate" (throws if missing)
# This stack holds one no-op resource and exists only to answer those two calls, so
# the upstream application code runs unmodified.
################################################################################

locals {
  metadata_stack_name = "${var.name}-metadata"
}

# The console links to this object where upstream offers the regional CloudFormation
# template; in this build regions are added with the dlt-region Terraform module.
resource "aws_s3_object" "regional_onboarding" {
  bucket       = module.storage.scenarios_bucket_name
  key          = "regional-template/README.txt"
  content_type = "text/plain"
  content      = <<-EOT
    This Distributed Load Testing hub (${var.name}) is managed by Terraform.
    Add a load-testing region by instantiating the dlt-region module with
    hub = module.hub.regional_inputs and a provider for the target region.
  EOT

  tags = local.tags
}

resource "aws_cloudformation_stack" "metadata" {
  name = local.metadata_stack_name

  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "(${var.solution_id}) Distributed Load Testing on AWS - Terraform metadata shim. Version ${var.solution_version}"
    Resources = {
      Placeholder = { Type = "AWS::CloudFormation::WaitConditionHandle" }
    }
    Outputs = merge(
      {
        SolutionTemplate = { Value = var.console_mode }
        SolutionUUID     = { Value = local.uuid }
        RegionalCFTemplate = {
          Value  = "https://${module.storage.scenarios_bucket_name}.s3.${local.region}.amazonaws.com/${aws_s3_object.regional_onboarding.key}"
          Export = { Name = "${local.metadata_stack_name}-RegionalCFTemplate" }
        }
      },
      var.deploy_mcp_server ? { McpEndpoint = { Value = module.mcp[0].gateway_url } } : {},
    )
  })

  tags = merge(local.tags, {
    SolutionVersion = var.solution_version
    ManagedBy       = "terraform"
  })
}
